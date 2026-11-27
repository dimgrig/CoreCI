#!/bin/sh
# CoreCI/scripts/deploy-linux.sh — cqtdeployer + Qt-libs copy + prune + sanity.
#
# Env (обязательные):
#   APP_NAME_BIN         имя бинаря (из appinfo.env — можно . /deploy/appinfo.env)
#   DIST_NAME            ModbusClientDistributionKit / SaksRenovaDistributionKit
#   QT_VERSION_MAJOR     5|6
#   CORE_LIBS            "libcore-lib libcore-journal-lib ..."
#
# Env (опциональные):
#   DEPLOY_DIR           /deploy
#   LOCAL_INSTALL        /opt/{app}/qt$N/<ver> — откуда копировать exe+appinfo
#   QT6_INSTALL_PREFIX   /opt/Qt/6.8.0/gcc_64 (для Qt6)
#   ARCH_TRIPLET         x86_64-linux-gnu | aarch64-linux-gnu | arm-linux-gnueabihf
#   EXTRA_LIBS           "libsaks-config-lib libsaks-db-lib ..." (опц.)
#   EXTRA_LIBDIRS        "/opt/saks/latest/lib" (опц.)
set -eu

: "${APP_NAME_BIN:?deploy-linux.sh: APP_NAME_BIN is required}"
: "${DIST_NAME:?deploy-linux.sh: DIST_NAME is required}"
: "${QT_VERSION_MAJOR:?deploy-linux.sh: QT_VERSION_MAJOR is required}"
: "${CORE_LIBS:?deploy-linux.sh: CORE_LIBS is required}"

DEPLOY_DIR="${DEPLOY_DIR:-/deploy}"
ARCH_TRIPLET="${ARCH_TRIPLET:-x86_64-linux-gnu}"
CORE_SDK="/opt/core/qt${QT_VERSION_MAJOR}/latest"
DIST="${DEPLOY_DIR}/${DIST_NAME}"

# Копируем exe+appinfo из install-дерева, если оно передано
if [ -n "${LOCAL_INSTALL:-}" ]; then
    mkdir -p "${DEPLOY_DIR}"
    cp "${LOCAL_INSTALL}/bin/${APP_NAME_BIN}" "${DEPLOY_DIR}/"
    cp "${LOCAL_INSTALL}/appinfo.env" "${DEPLOY_DIR}/appinfo.env" 2>/dev/null || true
fi

. "${DEPLOY_DIR}/appinfo.env"

if [ "${QT_VERSION_MAJOR}" = "6" ]; then
    QMAKE_BIN="${QT6_INSTALL_PREFIX}/bin/qmake"
    EXTRA_LIBDIR_FLAG="-libDir ${QT6_INSTALL_PREFIX}/lib"
    QT_LIBDIR="${QT6_INSTALL_PREFIX}/lib"
    QT_PLUGINS="${QT6_INSTALL_PREFIX}/plugins"
else
    QMAKE_BIN="$(command -v qmake)"
    EXTRA_LIBDIR_FLAG=""
    QT_LIBDIR="/usr/lib/${ARCH_TRIPLET}"
    QT_PLUGINS="/usr/lib/${ARCH_TRIPLET}/qt5/plugins"
fi

# Собираем флаги
EXTRA_LIBDIRS_FLAGS=""
for d in ${EXTRA_LIBDIRS:-}; do
    EXTRA_LIBDIRS_FLAGS="${EXTRA_LIBDIRS_FLAGS} -libDir ${d}"
done

EXTRA_LIBS_FLAGS=""
for lib in ${EXTRA_LIBS:-}; do
    EXTRA_LIBS_FLAGS="${EXTRA_LIBS_FLAGS} -extraLibs ${lib}.so"
done

CORE_LIBS_FLAGS=""
for lib in ${CORE_LIBS}; do
    CORE_LIBS_FLAGS="${CORE_LIBS_FLAGS} -extraLibs ${lib}.so"
done

mkdir -p "${DIST}"

# shellcheck disable=SC2086
cqtdeployer -bin "${DEPLOY_DIR}/${APP_NAME_BIN}" \
    -qmake "${QMAKE_BIN}" \
    -targetDir "${DIST}" \
    -libDir "${CORE_SDK}/lib" \
    ${EXTRA_LIBDIR_FLAG} \
    ${EXTRA_LIBDIRS_FLAGS} \
    ${CORE_LIBS_FLAGS} \
    ${EXTRA_LIBS_FLAGS}

# Явное копирование Core libs — cqtdeployer не всегда тянет всю SONAME-цепочку
mkdir -p "${DIST}/lib"
for lib in ${CORE_LIBS}; do
    if ls "${CORE_SDK}/lib/${lib}.so"* >/dev/null 2>&1; then
        cp -av "${CORE_SDK}/lib/${lib}.so"* "${DIST}/lib/"
    else
        echo "deploy-linux: FATAL: ${CORE_SDK}/lib/${lib}.so* not found" >&2
        exit 1
    fi
done

for d in ${EXTRA_LIBDIRS:-}; do
    if [ -d "$d" ]; then
        cp -av "$d"/*.so* "${DIST}/lib/" 2>/dev/null || true
    fi
done

# Qt libs
if [ "${QT_VERSION_MAJOR}" = "6" ]; then
    cp -d "${QT_LIBDIR}"/libQt6*.so* "${DIST}/lib/" 2>/dev/null || true
else
    for lib in Core DBus Gui Network PrintSupport SerialPort SerialBus Sql Svg Widgets XcbQpa; do
        cp -d "${QT_LIBDIR}/libQt5${lib}.so"* "${DIST}/lib/" 2>/dev/null || true
    done
fi

# Транзитивные зависимости (ICU, SSL, pcre2, zstd, …) — одинаково для qt5/qt6
for pat in 'libicu*.so*' 'libssl.so*' 'libcrypto*.so*' \
           'libpcre2-16.so*' 'libpcre2-8.so*' \
           'libzstd.so*' 'libdouble-conversion.so*' \
           'libmd4c.so*' 'libb2.so*'; do
    cp -d "${QT_LIBDIR}/"${pat} "${DIST}/lib/" 2>/dev/null || \
    cp -d "/usr/lib/${ARCH_TRIPLET}/"${pat} "${DIST}/lib/" 2>/dev/null || true
done

# Плагины
mkdir -p "${DIST}/plugins"
for plugin_dir in platforms imageformats iconengines styles sqldrivers tls platformthemes; do
    if [ -d "${QT_PLUGINS}/${plugin_dir}" ]; then
        cp -r "${QT_PLUGINS}/${plugin_dir}" "${DIST}/plugins/"
    fi
done

# Prune системных (glibc / font stack / zlib)
rm -f "${DIST}/lib/"libc.so* \
      "${DIST}/lib/"libm.so* \
      "${DIST}/lib/"libdl.so* \
      "${DIST}/lib/"libpthread.so* \
      "${DIST}/lib/"librt.so* \
      "${DIST}/lib/"libnsl.so* \
      "${DIST}/lib/"libresolv.so* \
      "${DIST}/lib/"libutil.so* \
      "${DIST}/lib/"libnss*.so* \
      "${DIST}/lib/"ld-linux*.so*
rm -f "${DIST}/lib/"libharfbuzz*.so* \
      "${DIST}/lib/"libfontconfig*.so* \
      "${DIST}/lib/"libfreetype*.so* \
      "${DIST}/lib/"libgraphite2*.so* \
      "${DIST}/lib/"libglib-2.0*.so* \
      "${DIST}/lib/"libgobject-2.0*.so* \
      "${DIST}/lib/"libgio-2.0*.so* \
      "${DIST}/lib/"libz.so* \
      "${DIST}/lib/"liblzma.so* \
      "${DIST}/lib/"libbz2.so* \
      "${DIST}/lib/"libpng*.so*
rm -f "${DIST}/lib/"libicuio.so* \
      "${DIST}/lib/"libicutest.so* \
      "${DIST}/lib/"libicutu.so*

# ── appinfo в DistributionKit ──
# install_desktop.sh / install_run.sh / uninstall_*.sh делают `source appinfo`.
# LOCAL_INSTALL уже передан из Dockerfile (= /opt/rv/qt6/<ver>).
_dk_root="${DEPLOY_DIR}/${DIST_NAME}"
_prefix="${LOCAL_INSTALL:-}"
if [ -n "${_prefix}" ] && [ -f "${_prefix}/appinfo.env" ]; then
    cp -f "${_prefix}/appinfo.env" "${_dk_root}/appinfo.env"
    cp -f "${_prefix}/appinfo.env" "${_dk_root}/appinfo"
fi
if [ -n "${_prefix}" ] && [ -f "${_prefix}/appinfo" ]; then
    cp -f "${_prefix}/appinfo" "${_dk_root}/appinfo"
fi

# Sanity
_err=0
if ls "${DIST}/lib/libc.so"* 2>/dev/null; then
    echo "deploy-linux: FATAL: glibc leaked" >&2; _err=1
fi
if ! ls "${DIST}/lib/libQt${QT_VERSION_MAJOR}Core.so"* >/dev/null 2>&1; then
    echo "deploy-linux: FATAL: libQt${QT_VERSION_MAJOR}Core not in bundle" >&2; _err=1
fi
if [ ! -f "${DIST}/bin/${APP_NAME_BIN}" ] && [ ! -f "${DIST}/${APP_NAME_BIN}" ]; then
    echo "deploy-linux: FATAL: ${APP_NAME_BIN} not in bundle" >&2; _err=1
fi
if [ ! -f "${DIST}/plugins/platforms/libqxcb.so" ]; then
    echo "deploy-linux: FATAL: libqxcb.so missing" >&2; _err=1
fi
if [ "${QT_VERSION_MAJOR}" = "6" ]; then
    for icu in libicui18n libicuuc libicudata; do
        if ! ls "${DIST}/lib/${icu}.so."* >/dev/null 2>&1; then
            echo "deploy-linux: FATAL: ${icu} missing (Qt6Core)" >&2; _err=1
        fi
    done
fi
[ "$_err" = "0" ] || exit 1

echo "deploy-linux: ${DIST_NAME} (Qt${QT_VERSION_MAJOR}): $(ls -1 "${DIST}/lib" | wc -l) libs"