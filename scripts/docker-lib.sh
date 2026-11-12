#!/usr/bin/env bash
# ============================================================================
# CoreCI/scripts/docker-lib.sh — generic driver for Core-based projects.
#
# Клиент (docker.sh) объявляет:
#   APP_NAME, APP_VERSION, PLATFORMS (declare -A)
#   [hooks]  extra_preflight_images, extra_build_args
# и вызывает  core_docker_main "$@".
#
# Команды:
#   base     — .ci/scripts/build-base-deps.sh
#   build    — docker compose -f docker-compose.build.yml build
#   export   — buildx --target export для всех PLATFORMS
#   test     — buildx --target test для linux-qt5/linux-qt6
#   mode     — dev|ci (auto-detect)
#   all      — base + build + export
#   help
#
# Env (те же, что раньше):
#   PLATFORMS, EXPORT_MODE, OUT_DIR, DEPLOY_ROOT, CI, CLEAN,
#   CACHE_FROM, CACHE_TO, CORE_SDK_VERSION, CORE_SDK_URL, CORE_SDK_REPO,
#   CORE_SDK_SHA256, QT6_INSTALL_PREFIX, INNOSETUP_IMAGE
# ============================================================================
set -euo pipefail

# ── locate project root: <project>/docker.sh sources this file as
#    <project>/.ci/scripts/docker-lib.sh, поэтому APP_ROOT определён
#    в клиенте ДО source. Если нет — ошибка. ──
: "${APP_ROOT:?docker-lib.sh: APP_ROOT must be set (cd to project root before sourcing)}"
: "${APP_NAME:?docker-lib.sh: APP_NAME must be set}"

# ── CoreCI submodule guard ───────────────────────────────────────────
[ -f "$APP_ROOT/.ci/scripts/detect-export-mode.sh" ] || {
    echo "ERROR: CoreCI submodule not initialized (need v0.2.0+)." >&2
    echo "  Run: git submodule update --init --recursive" >&2
    echo "       (cd .ci && git checkout v0.2.0)" >&2
    exit 1
}
source "$APP_ROOT/.ci/scripts/detect-export-mode.sh"

# ── Defaults для hooks (клиент может переопределить) ─────────────────
extra_preflight_images() { :; }
extra_build_args()       { :; }

# ── parse_platform_spec <spec> — eval key=value в caller scope ──────
parse_platform_spec() {
    local spec="$1" kv
    IFS=';' read -ra _kv <<< "$spec"
    for kv in "${_kv[@]}"; do
        [ -z "$kv" ] && continue
        # Валидация: только "name=value", имя — [a-z_]
        if [[ "$kv" =~ ^([a-z_][a-z0-9_]*)=(.*)$ ]]; then
            eval "${BASH_REMATCH[1]}=\$BASH_REMATCH[2]"
            eval "local _v_${BASH_REMATCH[1]}=\$BASH_REMATCH[2]"
        else
            echo "ERROR: bad platform spec token: '$kv'" >&2
            return 1
        fi
    done
}

# ── _cache_args — заполняет CACHE_ARGS по CACHE_FROM/CACHE_TO ───────
_cache_args() {
    CACHE_ARGS=()
    [ -n "${CACHE_FROM:-}" ] && CACHE_ARGS+=( --cache-from "$CACHE_FROM" )
    [ -n "${CACHE_TO:-}"   ] && CACHE_ARGS+=( --cache-to   "$CACHE_TO" )
}

# ── _core_sdk_sha <platform> <qt> <ver> — из SHA256SUMS ─────────────
_core_sdk_sha() {
    local platform="$1" qt="$2" ver="$3"
    local ext art repo sha
    case "$platform" in
        win32|win64) ext="zip" ;;
        *)           ext="tar.gz" ;;
    esac
    repo="${CORE_SDK_REPO:-dimgrig/Core}"
    art="Core-Releases-${ver}-${platform}-qt${qt}.${ext}"
    command -v curl >/dev/null 2>&1 || { echo ""; return 0; }
    sha="$(curl -fsSL --connect-timeout 15 --max-time 30 \
        "https://github.com/${repo}/releases/download/v${ver}/SHA256SUMS" 2>/dev/null \
        | awk -v f="$art" '$2 == f || $2 == "*"f {print $1; exit}')" || true
    echo "${sha:-}"
}

# ── _core_sdk_version — env → ../Core/VERSION → default ─────────────
_core_sdk_version() {
    if [ -n "${CORE_SDK_VERSION:-}" ]; then echo "$CORE_SDK_VERSION"; return; fi
    local core_ver="$APP_ROOT/../Core/VERSION"
    if [ -f "$core_ver" ]; then tr -d '[:space:]' < "$core_ver"; return; fi
    echo "1.1.0"
}

# ── _preflight — проверить, что base_image (+ extras) доступны ──────
_preflight() {
    local plat="$1" spec="${PLATFORMS[$1]}"
    (
        set +u
        eval "$(echo "$spec" | tr ';' '\n' | grep -E '^[a-z_]+=' | sed 's/^/local /;s/$/;/' | tr -d '\n' | sed 's/;/; /g')" 2>/dev/null || true
    ) 2>/dev/null
    local base_image=""
    # Проще: используем parse в subshell
    (
        parse_platform_spec "$spec"
        echo "${base_image:-}"
        extra_preflight_images "$plat"
    )
}

# ── export_one <platform> — одна платформа ──────────────────────────
export_one() {
    local plat="$1" spec="${PLATFORMS[$1]:-}"
    [ -z "$spec" ] && { echo "ERROR: platform '$plat' not in PLATFORMS" >&2; return 1; }

    (
        # Defaults для всех полей (клиент может не указывать неиспользуемые)
        dockerfile="" out_subdir="$plat" pkg_suffix="$plat"
        base_image="" buildx_platform="" cmake_cmd="cmake"
        qt_major="6" qt6_prefix="" toolchain="" sdk_platform=""
        mingw_triplet="" mingw_pei="" mingw_gcc_suffix=""

        parse_platform_spec "$spec"

        [ -n "$dockerfile" ] || { echo "ERROR: $plat: dockerfile not set" >&2; return 1; }

        echo
        echo "--- ${plat} (→ ${out_subdir}/, ${dockerfile}) ---"

        local core_sha=""
        if [ -n "${CORE_SDK_SHA256:-}" ]; then
            core_sha="$CORE_SDK_SHA256"
        elif [ -z "${CORE_SDK_URL:-}" ]; then
            core_sha="$(_core_sdk_sha "${sdk_platform:-linux-amd64}" "$qt_major" "$SDK_VER")"
        fi
        if [ -n "$core_sha" ]; then
            echo "    core-sdk sha256: ${core_sha}"
        else
            echo "    core-sdk sha256: <none> (cache-bust выключен; pass CORE_SDK_SHA256=…)"
        fi

        local out_dir="$OUT_DIR/$out_subdir"
        [ "$CLEAN" = "1" ] && { echo "=== CLEAN=1 → rm -rf $out_dir ==="; rm -rf "$out_dir"; }
        mkdir -p "$out_dir"

        local bargs=( --build-arg "BASE_DEPS_IMAGE=${base_image}"
                      --build-arg "CMAKE_CMD=${cmake_cmd}"
                      --build-arg "QT_VERSION_MAJOR=${qt_major}"
                      --build-arg "CORE_SDK_VERSION=${SDK_VER}"
                      --build-arg "CORE_SDK_URL=${CORE_SDK_URL:-}"
                      --build-arg "CORE_SDK_PLATFORM=${sdk_platform}"
                      --build-arg "CORE_SDK_SHA256=${core_sha}"
                      --build-arg "QT6_INSTALL_PREFIX=${qt6_prefix:-}"
                      --build-arg "CMAKE_TOOLCHAIN_FILE=${toolchain:-}" )
        [ -n "$qt6_prefix" ] && bargs+=( --build-arg "QT6_INSTALL_PREFIX=${qt6_prefix}" )
        [ -n "$toolchain"  ] && bargs+=( --build-arg "CMAKE_TOOLCHAIN_FILE=${toolchain}" )

        if [[ "$plat" == win-* ]]; then
            local qt_host_path=""
            [ "$qt_major" = "6" ] && qt_host_path="/opt/Qt/6.8.0/gcc_64"
            bargs+=( --build-arg "QT_HOST_PATH=${qt_host_path}"
                     --build-arg "MINGW_TRIPLET=${mingw_triplet}"
                     --build-arg "MINGW_PEI=${mingw_pei}"
                     --build-arg "MINGW_GCC_SUFFIX=${mingw_gcc_suffix}"
                     --build-arg "INNOSETUP_IMAGE=${INNOSETUP_IMAGE:-ghcr.io/dimgrig/innosetup-base:latest}" )
        fi

        # hooks: extra_build_args (по KEY=VALUE на строку)
        local _extra
        while IFS= read -r _extra; do
            [ -z "$_extra" ] && continue
            bargs+=( --build-arg "$_extra" )
        done < <(extra_build_args "$plat")

        bargs+=( --target export --output "type=local,dest=${out_dir}" )
        [ -n "$buildx_platform" ] && bargs+=( --platform "$buildx_platform" )

        # host.docker.internal для dev
        if [ -n "${CORE_SDK_URL:-}" ] && [[ "$CORE_SDK_URL" == http://host.docker.internal:* ]]; then
            bargs+=( --add-host host.docker.internal:host-gateway )
        fi

        _cache_args
        docker buildx build "${bargs[@]}" "${CACHE_ARGS[@]}" -f "$dockerfile" "$APP_ROOT"

        local fmt pkg
        case "$pkg_suffix" in win-*) fmt="zip" ;; *) fmt="tar.gz" ;; esac
        pkg="${APP_NAME}-${APP_VERSION}-${pkg_suffix}.${fmt}"
        if [ "$fmt" = "zip" ]; then
            ( cd "$out_dir" && zip -qr "../$pkg" . )
        else
            tar -czf "$OUT_DIR/$pkg" -C "$out_dir" .
        fi
        echo "  → $OUT_DIR/$pkg ($(du -h "$OUT_DIR/$pkg" | cut -f1))"
    )
}

# ── cmd_export ─────────────────────────────────────────────────────
cmd_export() {
    PLATFORMS_LIST="${PLATFORMS_LIST:-${PLATFORMS_ENV:-linux-qt6}}"
    CLEAN="${CLEAN:-0}"

    detect_export_mode || exit 1
    case "$EXPORT_MODE" in
        dev) DEPLOY_ROOT="${DEPLOY_ROOT:-$HOME/deploy/$APP_NAME}"; OUT_DIR="${OUT_DIR:-$DEPLOY_ROOT/$APP_VERSION}" ;;
        ci)  DEPLOY_ROOT="${DEPLOY_ROOT:-}";                       OUT_DIR="${OUT_DIR:-$PWD/dist}" ;;
    esac
    echo "=== mode: ${EXPORT_MODE} (OUT_DIR=${OUT_DIR}, DEPLOY_ROOT=${DEPLOY_ROOT:-<none>}) ==="

    local SDK_VER; SDK_VER="$(_core_sdk_version)"
    echo "=== ${APP_NAME} ${APP_VERSION} → ${OUT_DIR} (Core SDK ${SDK_VER}) ==="
    echo "=== PLATFORMS: ${PLATFORMS_LIST} ==="
    mkdir -p "$OUT_DIR"

    # pre-flight
    local plat spec base_img extra missing=()
    read -ra _plats <<< "$PLATFORMS_LIST"
    for plat in "${_plats[@]}"; do
        spec="${PLATFORMS[$plat]:-}"
        [ -z "$spec" ] && { echo "ERROR: unknown platform '$plat'" >&2; exit 1; }

        local imgs=()
        base_img="$( (parse_platform_spec "$spec"; echo "${base_image:-}") )"
        [ -n "$base_img" ] && imgs+=("$base_img")
        while IFS= read -r extra; do
            [ -n "$extra" ] && imgs+=("$extra")
        done < <(extra_preflight_images "$plat")

        for img in "${imgs[@]}"; do
            local ok=0
            docker image inspect "$img" >/dev/null 2>&1 && ok=1
            [ "$ok" = 0 ] && docker manifest inspect "$img" >/dev/null 2>&1 && ok=1
            [ "$ok" = 0 ] && missing+=("$img  (platform $plat)")
        done
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "ERROR: base-deps images недоступны ни локально, ни в registry:" >&2
        printf '  - %s\n' "${missing[@]}" >&2
        echo >&2
        echo "В dev:   ./docker.sh base" >&2
        echo "В CI:    проверьте, что base-deps опубликованы в ghcr" >&2
        exit 1
    fi

    for plat in "${_plats[@]}"; do
        export_one "$plat" || exit 1
    done

    if [ -n "$DEPLOY_ROOT" ]; then
        mkdir -p "$DEPLOY_ROOT"
        if [ -e "${DEPLOY_ROOT}/latest" ] && [ ! -L "${DEPLOY_ROOT}/latest" ]; then
            local _bak="${DEPLOY_ROOT}/latest.bak.$(date +%Y%m%d-%H%M%S)"
            echo "WARN: ${DEPLOY_ROOT}/latest is a dir → moving to ${_bak}"
            mv "${DEPLOY_ROOT}/latest" "$_bak"
        fi
        ln -sfn "$OUT_DIR" "${DEPLOY_ROOT}/latest"
        echo; echo "=== latest -> ${OUT_DIR} ==="
    fi

    echo; echo "=== Done ==="
    find "$OUT_DIR" -maxdepth 1 -type f \
        \( -name "${APP_NAME}-*.tar.gz" -o -name "${APP_NAME}-*.zip" \) \
        -exec ls -lh {} \; 2>/dev/null || true
}

# ── cmd_test ───────────────────────────────────────────────────────
cmd_test() {
    PLATFORMS_LIST="${PLATFORMS_LIST:-linux-qt6}"
    local SDK_VER; SDK_VER="$(_core_sdk_version)"
    local tested=0 plat spec base_img qt_major qt6_prefix dockerfile
    read -ra _plats <<< "$PLATFORMS_LIST"

    for plat in "${_plats[@]}"; do
        case "$plat" in
            linux-qt6|linux-qt5) ;;
            *) echo "NOTE: test supports only linux-qt5/linux-qt6, skipping '$plat'"; continue ;;
        esac
        spec="${PLATFORMS[$plat]:-}"
        [ -z "$spec" ] && continue

        local core_sha=""
        if [ -n "${CORE_SDK_SHA256:-}" ]; then
            core_sha="$CORE_SDK_SHA256"
        elif [ -z "${CORE_SDK_URL:-}" ]; then
            core_sha="$(_core_sdk_sha linux-amd64 "$( (parse_platform_spec "$spec"; echo "$qt_major") )" "$SDK_VER")"
        fi

        (
            parse_platform_spec "$spec"
            echo "--- test ${plat} (base: ${base_image}) ---"
            local targs=( --target test
                          --build-arg "BASE_DEPS_IMAGE=${base_image}"
                          --build-arg "CMAKE_CMD=${cmake_cmd:-cmake}"
                          --build-arg "QT_VERSION_MAJOR=${qt_major}"
                          --build-arg "CORE_SDK_VERSION=${SDK_VER}"
                          --build-arg "CORE_SDK_SHA256=${core_sha}" )
            [ -n "${qt6_prefix:-}" ] && targs+=( --build-arg "QT6_INSTALL_PREFIX=${qt6_prefix}" )
            if [ -n "${CORE_SDK_URL:-}" ] && [[ "$CORE_SDK_URL" == http://host.docker.internal:* ]]; then
                targs+=( --add-host host.docker.internal:host-gateway )
            fi
            _cache_args
            docker buildx build "${targs[@]}" "${CACHE_ARGS[@]}" -f "$dockerfile" "$APP_ROOT"
        )
        tested=$((tested+1))
    done
    [ "$tested" -gt 0 ] || { echo "ERROR: no linux-qt5/linux-qt6 in '$PLATFORMS_LIST'" >&2; exit 1; }
    echo "=== test OK (${tested} platform(s)) ==="
}

# ── cmd_base / cmd_build ───────────────────────────────────────────
cmd_base()  { bash "$APP_ROOT/.ci/scripts/build-base-deps.sh" "$@"; }
cmd_build() {
    _base_deps_env
    export CORE_SDK_VERSION="$(_core_sdk_version)"
    export CORE_SDK_URL="${CORE_SDK_URL:-}"
    # клиент может добавить pre-export sha'ы через hook `pre_export_shas`
    declare -f pre_export_shas >/dev/null && pre_export_shas
    docker compose -f docker-compose.build.yml build "$@"
}

# ── core_docker_main — dispatch ────────────────────────────────────
core_docker_main() {
    cd "$APP_ROOT"
    [ -f VERSION ] || { echo "ERROR: VERSION not in $APP_ROOT" >&2; exit 1; }

    local cmd="${1:-}"; shift || true
    case "$cmd" in
        base)    cmd_base "$@" ;;
        build)   cmd_build "$@" ;;
        export)  cmd_export "$@" ;;
        test)    cmd_test "$@" ;;
        mode)    detect_export_mode || exit 1; echo "$EXPORT_MODE" ;;
        all)     cmd_base; cmd_build; cmd_export "$@" ;;
        help|-h|--help) sed -n '3,22p' "$APP_ROOT/.ci/scripts/docker-lib.sh"; exit 0 ;;
        "")      sed -n '3,22p' "$APP_ROOT/.ci/scripts/docker-lib.sh"; exit 1 ;;
        *)       echo "ERROR: unknown command '$cmd' (base|build|export|test|mode|all|help)" >&2; exit 1 ;;
    esac
}