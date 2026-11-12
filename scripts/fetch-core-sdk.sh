#!/usr/bin/env bash
# ============================================================================
# fetch-core-sdk.sh — скачать и распаковать Core SDK.
#
# Интерфейс совместим с Core / Saks / MODBUS-* Dockerfile:
#   fetch-core-sdk.sh [VERSION] [URL] [DEST] [QT_MAJOR]
#
#   VERSION   — версия Core SDK (default: $CORE_SDK_VERSION или 1.1.0)
#   URL       — прямой URL архива ("" → собирается из REPO/VERSION/PLATFORM/QT)
#   DEST      — куда распаковать ("" → $HOME/.local/core/qt${QT_MAJOR}/${VERSION}).
#               В контейнере с /opt writable и пустым DEST: /opt/core/$VERSION.
#   QT_MAJOR  — 5 или 6 (default: $QT_VERSION_MAJOR или 5)
#
# Env:
#   CORE_SDK_REPO      default: dimgrig/Core
#   CORE_SDK_PLATFORM  default: auto по uname (linux-amd64 / linux-arm64 / win64)
#   CORE_SDK_VERSION   default: 1.1.0 (перебивается $1)
#   QT_VERSION_MAJOR   default: 5     (перебивается $4)
# ============================================================================
set -euo pipefail

VERSION="${1:-${CORE_SDK_VERSION:-1.1.0}}"
URL_ARG="${2:-}"
DEST_ARG="${3:-}"
QT_MAJOR="${4:-${QT_VERSION_MAJOR:-5}}"

REPO="${CORE_SDK_REPO:-dimgrig/Core}"
PLATFORM="${CORE_SDK_PLATFORM:-}"

# ── auto-detect platform ────────────────────────────────────────────────────
if [ -z "$PLATFORM" ]; then
    ARCH="$(uname -m 2>/dev/null || echo unknown)"
    case "$ARCH" in
        x86_64|amd64)   PLATFORM="linux-amd64" ;;
        aarch64|arm64)  PLATFORM="linux-arm64" ;;
        *)
            case "${OSTYPE:-}" in
                msys*|cygwin*|win32*) PLATFORM="win64" ;;
                *)                    PLATFORM="linux-amd64" ;;
            esac
            ;;
    esac
fi

# ── ART / URL / EXT ─────────────────────────────────────────────────────────
if [ -n "$URL_ARG" ]; then
    URL="$URL_ARG"
    ART="$(basename "$URL")"
    case "$ART" in
        *.zip) EXT="zip" ;;
        *)     EXT="tar.gz" ;;
    esac
else
    case "$PLATFORM" in
        win32|win64) EXT="zip" ;;
        *)           EXT="tar.gz" ;;
    esac
    ART="Core-Releases-${VERSION}-${PLATFORM}-qt${QT_MAJOR}.${EXT}"
    URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ART}"
fi

# ── DEST ────────────────────────────────────────────────────────────────────
# "" + /opt writable (root в контейнере)  → /opt/core/$VERSION
# "" + /opt не writable (dev на хосте)    → ~/.local/core/qt$N/$VERSION
# Явный DEST_ARG                          → используем как есть
if [ -z "$DEST_ARG" ]; then
    if [ -w /opt ]; then
        DEST="/opt/core/${VERSION}"
    else
        DEST="${HOME:-/tmp}/.local/core/qt${QT_MAJOR}/${VERSION}"
    fi
else
    DEST="$DEST_ARG"
fi

# ── Идемпотентность ─────────────────────────────────────────────────────────
# Если SDK пришёл не через этот скрипт (например, забит в core-builder-*
# через cmake --install), marker-файла нет — не доверяем, качаем заново.
_sha_marker="$DEST/lib/cmake/Core/.sdk-sha256"

if [ -n "${CORE_SDK_SHA256:-}" ]; then
    _existing_sha="$(cat "$_sha_marker" 2>/dev/null || echo '')"
    if [ -f "$DEST/lib/cmake/Core/CoreConfig.cmake" ] && [ "$_existing_sha" = "$CORE_SDK_SHA256" ]; then
        echo "Core SDK ${VERSION} (Qt${QT_MAJOR}) at ${DEST} already matches sha ${CORE_SDK_SHA256}"
        exit 0
    fi
    if [ -f "$DEST/lib/cmake/Core/CoreConfig.cmake" ] && [ -z "$_existing_sha" ]; then
        echo "Core SDK ${VERSION} at ${DEST} has no SHA marker (baked into base image?) — re-fetching"
    fi
    # fall through к download
else
    if [ -f "$DEST/lib/cmake/Core/CoreConfig.cmake" ]; then
        echo "Core SDK ${VERSION} (Qt${QT_MAJOR}) already at ${DEST}"
        exit 0
    fi
fi

mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── Downloader: curl → wget ─────────────────────────────────────────────────
_download() {
    local url="$1" out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL \
            --retry 5 \
            --retry-delay 5 \
            --retry-all-errors \
            --retry-max-time 600 \
            --connect-timeout 30 \
            --max-time 7200 \
            -o "$out" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --tries=5 --timeout=60 --waitretry=5 -O "$out" "$url"
    else
        echo "ERROR: neither curl nor wget available" >&2
        return 1
    fi
}

echo "Downloading ${URL}"
_download "$URL" "$TMP/$ART"

# ── SHA256 (опционально) ────────────────────────────────────────────────────
if [ -n "${CORE_SDK_SHA256:-}" ]; then
    EXPECTED="$CORE_SDK_SHA256"
else
    SHA_URL="https://github.com/${REPO}/releases/download/v${VERSION}/SHA256SUMS"
    if _download "$SHA_URL" "$TMP/SHA256SUMS" 2>/dev/null; then
        EXPECTED="$(awk -v f="$ART" '$2 == f || $2 == "*"f {print $1; exit}' "$TMP/SHA256SUMS")"
    else
        EXPECTED=""
    fi
fi
if [ -n "${EXPECTED:-}" ]; then
    ACTUAL="$(sha256sum "$TMP/$ART" | awk '{print $1}')"
    if [ "$ACTUAL" != "$EXPECTED" ]; then
        echo "ERROR: SHA256 mismatch for ${ART}" >&2
        echo "  expected: ${EXPECTED}" >&2
        echo "  actual:   ${ACTUAL}" >&2
        exit 1
    fi
    echo "SHA256 OK"
fi

# ── Extract ─────────────────────────────────────────────────────────────────
case "$EXT" in
    zip)
        if command -v unzip >/dev/null 2>&1; then
            unzip -q "$TMP/$ART" -d "$DEST"
        elif command -v 7z >/dev/null 2>&1; then
            7z x -y -o"$DEST" "$TMP/$ART" >/dev/null
        elif command -v 7za >/dev/null 2>&1; then
            7za x -y -o"$DEST" "$TMP/$ART" >/dev/null
        elif command -v bsdtar >/dev/null 2>&1; then
            bsdtar xf "$TMP/$ART" -C "$DEST"
        elif command -v python3 >/dev/null 2>&1; then
            python3 -m zipfile -e "$TMP/$ART" "$DEST"
        else
            echo "ERROR: no unzip/7z/7za/bsdtar/python3 for .zip extraction" >&2
            exit 1
        fi
        ;;
    *)
        tar -xzf "$TMP/$ART" -C "$DEST"
        ;;
esac

# ── Flatten (если архив распаковался в подкаталог) ──────────────────────────
if [ ! -f "$DEST/lib/cmake/Core/CoreConfig.cmake" ]; then
    SUB="$(find "$DEST" -name CoreConfig.cmake -path '*/cmake/Core/*' 2>/dev/null | head -1 || true)"
    if [ -n "${SUB:-}" ]; then
        SUBROOT="$(dirname "$(dirname "$(dirname "$(dirname "$SUB")")")")"
        if [ "$SUBROOT" != "$DEST" ] && [ -d "$SUBROOT" ]; then
            echo "Flattening extracted dir ${SUBROOT} → ${DEST}"
            shopt -s dotglob
            mv "$SUBROOT"/* "$DEST"/ 2>/dev/null || true
            shopt -u dotglob
            rm -rf "$SUBROOT"
        fi
    fi
fi

if [ ! -f "$DEST/lib/cmake/Core/CoreConfig.cmake" ]; then
    echo "ERROR: CoreConfig.cmake not found in ${DEST}" >&2
    exit 1
fi

# ── сохранение SHA ─────────────────────────────────
if [ -n "${CORE_SDK_SHA256:-}" ]; then
    echo "$CORE_SDK_SHA256" > "$DEST/lib/cmake/Core/.sdk-sha256"
fi

# ── Symlink latest (только если DEST авто) ─────────────────────────────────
if [ -z "$DEST_ARG" ]; then
    PARENT="$(dirname "$DEST")"
    ln -sfn "$(basename "$DEST")" "${PARENT}/latest"
    echo "Symlink: ${PARENT}/latest → ${DEST}"
fi

echo "Core SDK ${VERSION} (Qt${QT_MAJOR}, ${PLATFORM}) installed to ${DEST}"