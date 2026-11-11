#!/usr/bin/env bash
# CoreCI/scripts/build-linux.sh — сборка Core-based приложения на Linux-хосте.
#
# Запуск из корня проекта:
#   ./.ci/scripts/build-linux.sh
#   ./.ci/scripts/build-linux.sh --smoke
#   ./.ci/scripts/build-linux.sh --no-fetch     # CORE_SDK_ROOT из env
#   ./.ci/scripts/build-linux.sh --version 1.1.0
#   ./.ci/scripts/build-linux.sh --build-type Debug
#   ./.ci/scripts/build-linux.sh --clean
#   ./.ci/scripts/build-linux.sh --install-sdk  # в ~/.local/core/qt<N>/<ver>/
#
# Env:
#   CORE_SDK_VERSION (def 1.1.0)         — версия Core SDK
#   CORE_SDK_REPO    (def dimgrig/Core)  — репо релизов
#   CORE_SDK_ROOT    — путь к SDK (с --no-fetch)
set -euo pipefail

# ── Robus-детект корня проекта ──────────────────────────────────
# Скрипт живёт в <project>/.ci/scripts/build-linux.sh — REPO_ROOT
# на два уровня выше. Если запущен из CoreCI/scripts/ (для тестов),
# REPO_ROOT = CoreCI/.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$SCRIPT_DIR/../.." ]; then
    REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
else
    echo "ERROR: cannot detect project root from $SCRIPT_DIR" >&2
    exit 1
fi
FETCH="$SCRIPT_DIR/fetch-core-sdk.sh"
[ -x "$FETCH" ] || { echo "ERROR: $FETCH missing/not executable" >&2; exit 1; }

VERSION="${CORE_SDK_VERSION:-1.1.0}"
REPO="${CORE_SDK_REPO:-dimgrig/Core}"
BUILD_TYPE="Release"
BUILD_DIR="build"
DO_CLEAN=0
DO_SMOKE=0
NO_FETCH=0
INSTALL_SDK=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)        DO_CLEAN=1 ;;
        --smoke)        DO_SMOKE=1 ;;
        --no-fetch)     NO_FETCH=1 ;;
        --install-sdk)  INSTALL_SDK=1 ;;
        --version)      VERSION="$2"; shift ;;
        --build-type)   BUILD_TYPE="$2"; shift ;;
        --build-dir)    BUILD_DIR="$2"; shift ;;
        -h|--help)      sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
    shift
done

cd "$REPO_ROOT"
echo "== build =="
echo "  source : $REPO_ROOT"
echo "  sdk    : $VERSION (repo ${REPO})"
echo "  type   : $BUILD_TYPE"
echo "  build  : $BUILD_DIR"

if [[ "$INSTALL_SDK" == "1" ]]; then
    # Detect QT_MAJOR из qmake path, если доступен (иначе 5)
    QT_MAJOR="${QT_VERSION_MAJOR:-5}"
    if command -v qmake >/dev/null 2>&1; then
        _qmv="$(qmake -query QT_VERSION 2>/dev/null | cut -d. -f1 || true)"
        [ -n "${_qmv:-}" ] && QT_MAJOR="$_qmv"
    fi
    DEST="$HOME/.local/core/qt${QT_MAJOR}/${VERSION}"
    "$FETCH" "$VERSION" "" "$DEST" "$QT_MAJOR"
    mkdir -p "$(dirname "$DEST")"
    ln -sfn "$VERSION" "$(dirname "$DEST")/latest"
    export CORE_SDK_ROOT="$DEST"
    NO_FETCH=1
fi

if [[ "$DO_CLEAN" == "1" && -d "$BUILD_DIR" ]]; then
    echo "→ rm -rf $BUILD_DIR"
    rm -rf "$BUILD_DIR"
fi

if ! command -v qmake >/dev/null 2>&1 && ! command -v qmake-qt5 >/dev/null 2>&1; then
    echo "ERROR: qmake not in PATH." >&2
    echo "Install: sudo apt install qtbase5-dev qtbase5-dev-tools qttools5-dev-tools \\" >&2
    echo "         libqt5serialport5-dev libqt5serialbus5-dev libqt5svg5-dev" >&2
    exit 1
fi

CMAKE_ARGS=(-DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DCMAKE_COLOR_DIAGNOSTICS=ON)

if [[ "$NO_FETCH" == "1" ]]; then
    if [[ -z "${CORE_SDK_ROOT:-}" ]]; then
        echo "ERROR: --no-fetch requires CORE_SDK_ROOT in env" >&2
        exit 1
    fi
    if [[ ! -f "$CORE_SDK_ROOT/lib/cmake/Core/CoreConfig.cmake" ]]; then
        echo "ERROR: CoreConfig.cmake not found in $CORE_SDK_ROOT" >&2
        exit 1
    fi
    echo "→ using SDK from $CORE_SDK_ROOT"
    CMAKE_ARGS+=(-DCMAKE_PREFIX_PATH="$CORE_SDK_ROOT")
else
    echo "→ fetch Core SDK $VERSION from GitHub"
    CMAKE_ARGS+=(-DCORE_SDK_FETCH=ON -DCORE_SDK_VERSION="$VERSION"
                 -DCORE_SDK_REPO="$REPO")
fi

echo "→ cmake -B $BUILD_DIR ${CMAKE_ARGS[*]}"
cmake -B "$BUILD_DIR" "${CMAKE_ARGS[@]}"

echo "→ cmake --build $BUILD_DIR -j$(nproc)"
cmake --build "$BUILD_DIR" -j"$(nproc)"

if [[ "$DO_SMOKE" == "1" ]]; then
    # Auto-detect executable: приоритет — $BUILD_DIR/<name> без .so
    EXE="$(find "$BUILD_DIR" -maxdepth 1 -type f -executable ! -name '*.so*' ! -name '*.a' 2>/dev/null | head -1)"
    if [[ -z "$EXE" ]]; then
        echo "ERROR: no executable in $BUILD_DIR" >&2
        exit 1
    fi
    echo "→ smoke: $EXE"
    set +e
    QT_QPA_PLATFORM=offscreen MODBUS_SMOKE=1 "$EXE"
    RC=$?
    set -e
    [[ $RC -ne 0 ]] && { echo "ERROR: smoke failed (exit $RC)" >&2; exit $RC; }
    echo "✓ smoke OK"
fi

echo
echo "== Done =="
echo "  build: $REPO_ROOT/$BUILD_DIR"