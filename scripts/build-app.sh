#!/bin/sh
# CoreCI/scripts/build-app.sh — cmake configure+build+install в контейнере.
#
# Env (обязательные):
#   APP_NAME             имя исполняемого файла (modbus-client, saks-renova)
#   QT_VERSION_MAJOR     5|6
#   CORE_INSTALL_BASE    /opt/{app}
#
# Env (опциональные):
#   BUILD_TYPE           Release (по умолчанию)
#   CMAKE_CMD            cmake | i686-w64-mingw32-cmake (по умолчанию cmake)
#   QT6_INSTALL_PREFIX   /opt/Qt/6.8.0/gcc_64 (для Qt6)
#   QT_HOST_PATH         /opt/Qt/6.8.0/gcc_64 (для win cross)
#   CMAKE_TOOLCHAIN_FILE (для win cross)
#   BUILD_TESTING        OFF (для build-стадии)
#   CMAKE_EXTRA_ARGS     доп. флаги cmake
#   CORE_LIBS            "libcore-lib libcore-journal-lib ..." — копировать .so рядом с бинарём
#
# Оставляет установку в $CORE_INSTALL_BASE/qt$N/<ver>/ + симлинк latest.
set -eu

: "${APP_NAME:?build-app.sh: APP_NAME is required}"
: "${QT_VERSION_MAJOR:?build-app.sh: QT_VERSION_MAJOR is required}"
: "${CORE_INSTALL_BASE:?build-app.sh: CORE_INSTALL_BASE is required}"

BUILD_TYPE="${BUILD_TYPE:-Release}"
CMAKE_CMD="${CMAKE_CMD:-cmake}"
BUILD_TESTING="${BUILD_TESTING:-OFF}"

V="$(tr -d '[:space:]' < VERSION)"
DEST="${CORE_INSTALL_BASE}/qt${QT_VERSION_MAJOR}/${V}"
CORE_SDK="/opt/core/qt${QT_VERSION_MAJOR}/latest"

CMAKE_PREFIX_ARG=""
if [ "${QT_VERSION_MAJOR}" = "6" ] && [ -n "${QT6_INSTALL_PREFIX:-}" ]; then
    CMAKE_PREFIX_ARG="-DCMAKE_PREFIX_PATH=${QT6_INSTALL_PREFIX}"
fi

CMAKE_TOOLCHAIN_ARG=""
if [ -n "${CMAKE_TOOLCHAIN_FILE:-}" ]; then
    CMAKE_TOOLCHAIN_ARG="-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}"
fi

HOST_PATH_ARG=""
if [ -n "${QT_HOST_PATH:-}" ]; then
    HOST_PATH_ARG="-DQT_HOST_PATH=${QT_HOST_PATH}"
fi

mkdir -p "${CORE_INSTALL_BASE}/qt${QT_VERSION_MAJOR}"

# ── appinfo: проброс ENV → CMake (используется core_write_appinfo) ──
for _v in APP_NAME_RU APP_NAME_EN APP_NAME_BIN ICON_NAME; do
    eval "_val=\${$_v:-}"
    if [ -n "${_val}" ]; then
        CMAKE_EXTRA_ARGS="${CMAKE_EXTRA_ARGS:-} -D${_v}=${_val}"
    fi
done

# shellcheck disable=SC2086
${CMAKE_CMD} -S . -B build \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DBUILD_TESTING="${BUILD_TESTING}" \
    -DQT_VERSION_MAJOR="${QT_VERSION_MAJOR}" \
    -DCore_DIR="${CORE_SDK}/lib/cmake/Core" \
    -DCMAKE_INSTALL_PREFIX="${DEST}" \
    ${CMAKE_PREFIX_ARG} \
    ${CMAKE_TOOLCHAIN_ARG} \
    ${HOST_PATH_ARG} \
    ${CMAKE_EXTRA_ARGS:-}

${CMAKE_CMD} --build build -j"$(nproc)"
${CMAKE_CMD} --install build

if [ ! -f "${DEST}/bin/${APP_NAME}" ] && [ ! -f "${DEST}/bin/${APP_NAME}.exe" ]; then
    echo "build-app: FATAL: ${APP_NAME}{,.exe} not in ${DEST}/bin/" >&2
    ls -la "${DEST}/bin/" 2>/dev/null || true
    exit 1
fi
if [ -f "${DEST}/appinfo.env" ] && [ ! -f "${DEST}/appinfo" ]; then
    cp "${DEST}/appinfo.env" "${DEST}/appinfo"
fi
if [ ! -f "${DEST}/appinfo.env" ]; then
    echo "build-app: FATAL: appinfo.env not installed" >&2
    exit 1
fi

ln -sfn "${DEST}" "${CORE_INSTALL_BASE}/qt${QT_VERSION_MAJOR}/latest"

# Копия Core SDK libs рядом с бинарём (полезно cqtdeployer, чтобы не гонять -libDir)
mkdir -p "${DEST}/lib"
for lib in ${CORE_LIBS:-}; do
    if ls "${CORE_SDK}/lib/${lib}.so"* >/dev/null 2>&1; then
        cp -a "${CORE_SDK}/lib/${lib}.so"* "${DEST}/lib/"
    elif ls "${CORE_SDK}/bin/${lib}.dll" >/dev/null 2>&1; then
        cp -a "${CORE_SDK}/bin/${lib}.dll" "${DEST}/lib/" 2>/dev/null || true
    fi
done

echo "build-app: installed ${DEST}"