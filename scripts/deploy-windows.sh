##!/bin/bash
# CoreCI/scripts/deploy-windows.sh — DLL copy + MinGW runtime + transitive closure.
#
# Env (обязательные):
#   APP_NAME_BIN     имя exe (modbus-client)
#   DIST_NAME        ModbusClientDistributionKit / SaksRenovaDistributionKit
#   QT_VERSION_MAJOR 5|6
#   MINGW_TRIPLET    i686-w64-mingw32 | x86_64-w64-mingw32
#   MINGW_PEI        pei-i386 | pei-x86-64
#   MINGW_GCC_SUFFIX dw2-1 | seh-1
#   CORE_LIBS        "libcore-lib libcore-journal-lib ..."
#
# Env (опциональные):
#   DEPLOY_DIR       /deploy
#   LOCAL_INSTALL    /opt/{app}/qt$N/<ver>
#   QT6_INSTALL_PREFIX /opt/Qt/6.8.0/mingw_64 (для Qt6)
#   EXTRA_LIBS       "libsaks-config-lib ..."
#   EXTRA_LIBDIRS    "/opt/saks/latest/bin" (опц., откуда копировать .dll)
#   ICON_SRC         путь к .ico
#   CONFIG_INI       путь к config.ini
set -eu
SHELL=/bin/bash

: "${APP_NAME_BIN:?}"
: "${DIST_NAME:?}"
: "${QT_VERSION_MAJOR:?}"
: "${MINGW_TRIPLET:?}"
: "${MINGW_PEI:?}"
: "${MINGW_GCC_SUFFIX:?}"
: "${CORE_LIBS:?}"

DEPLOY_DIR="${DEPLOY_DIR:-/deploy}"
CORE_SDK="/opt/core/qt${QT_VERSION_MAJOR}/latest"
DIST="${DEPLOY_DIR}/${DIST_NAME}"
SYSROOT="/usr/${MINGW_TRIPLET}"

if [ -n "${LOCAL_INSTALL:-}" ]; then
    mkdir -p "${DEPLOY_DIR}"
    cp "${LOCAL_INSTALL}/bin/${APP_NAME_BIN}.exe" "${DEPLOY_DIR}/"
    cp "${LOCAL_INSTALL}/appinfo.env" "${DEPLOY_DIR}/appinfo.env" 2>/dev/null || true
fi

. "${DEPLOY_DIR}/appinfo.env"

mkdir -p "${DIST}"
cp "${DEPLOY_DIR}/${APP_NAME_BIN}.exe" "${DIST}/"
[ -n "${ICON_SRC:-}" ] && [ -f "$ICON_SRC" ] && cp "$ICON_SRC" "${DIST}/modbus.ico"
[ -n "${CONFIG_INI:-}" ] && [ -f "$CONFIG_INI" ] && cp "$CONFIG_INI" "${DIST}/config.ini"

# Core libs
for lib in ${CORE_LIBS}; do
    cp "${CORE_SDK}/bin/${lib}.dll" "${DIST}/"
done

# Extra libs
for d in ${EXTRA_LIBDIRS:-}; do
    for lib in ${EXTRA_LIBS:-}; do
        cp "${d}/${lib}.dll" "${DIST}/" 2>/dev/null || true
    done
done

# Qt DLL
if [ "${QT_VERSION_MAJOR}" = "6" ]; then
    cp "${QT6_INSTALL_PREFIX}/bin/"Qt6*.dll "${DIST}/"
    cp "${QT6_INSTALL_PREFIX}/bin/"libssl*.dll    "${DIST}/" 2>/dev/null || true
    cp "${QT6_INSTALL_PREFIX}/bin/"libcrypto*.dll "${DIST}/" 2>/dev/null || true
    cp "${QT6_INSTALL_PREFIX}/bin/"libzstd*.dll   "${DIST}/" 2>/dev/null || true
    for plugin_dir in platforms imageformats iconengines styles sqldrivers tls bearer networkinformation; do
        if [ -d "${QT6_INSTALL_PREFIX}/plugins/${plugin_dir}" ]; then
            cp -r "${QT6_INSTALL_PREFIX}/plugins/${plugin_dir}" "${DIST}/"
        fi
    done
else
    cp /usr/i686-w64-mingw32/bin/Qt5*.dll "${DIST}/" 2>/dev/null || true
    for plugin_dir in platforms imageformats iconengines styles sqldrivers bearer; do
        if [ -d "/usr/i686-w64-mingw32/lib/qt/plugins/${plugin_dir}" ]; then
            cp -r "/usr/i686-w64-mingw32/lib/qt/plugins/${plugin_dir}" "${DIST}/"
        fi
    done
fi

# Каталог runtime того самого компилятора, которым собраны exe и наши DLL
GCC_DIR="$(dirname "$(${MINGW_TRIPLET}-g++ -print-libgcc-file-name)")"
echo "deploy-windows: compiler runtime dir = ${GCC_DIR}"

# MinGW runtime (явно, с проверкой PEI)
for dll in libstdc++-6.dll libwinpthread-1.dll; do
    src=""
    for cand in \
        "${GCC_DIR}/$dll" \
        "${SYSROOT}/bin/$dll" \
        "${SYSROOT}/lib/$dll" \
        "/usr/lib/gcc/${MINGW_TRIPLET}/13-posix/$dll" \
        "/usr/lib/gcc/${MINGW_TRIPLET}/12-posix/$dll" \
        "/usr/lib/gcc/${MINGW_TRIPLET}/13-win32/$dll" \
        "/usr/lib/gcc/${MINGW_TRIPLET}/12-win32/$dll" \
        "${QT6_INSTALL_PREFIX:+$QT6_INSTALL_PREFIX/bin/$dll}"; do
        [ -n "$cand" ] && [ -f "$cand" ] && { src="$cand"; break; }
    done
    [ -n "$src" ] || { echo "deploy-windows: FATAL: $dll not found" >&2; exit 1; }
    if ! ${MINGW_TRIPLET}-objdump -f "$src" 2>/dev/null | grep -q "${MINGW_PEI}"; then
        echo "deploy-windows: FATAL: $src is not ${MINGW_PEI}" >&2; exit 1
    fi
    cp -a "$src" "${DIST}/"
done

libgcc_src=""
for cand in \
    "${GCC_DIR}/libgcc_s_${MINGW_GCC_SUFFIX}.dll" \
    "${SYSROOT}/bin/libgcc_s_${MINGW_GCC_SUFFIX}.dll" \
    "/usr/lib/gcc/${MINGW_TRIPLET}/13-posix/libgcc_s_${MINGW_GCC_SUFFIX}.dll" \
    "/usr/lib/gcc/${MINGW_TRIPLET}/12-posix/libgcc_s_${MINGW_GCC_SUFFIX}.dll" \
    "/usr/lib/gcc/${MINGW_TRIPLET}/13-win32/libgcc_s_${MINGW_GCC_SUFFIX}.dll" \
    "/usr/lib/gcc/${MINGW_TRIPLET}/12-win32/libgcc_s_${MINGW_GCC_SUFFIX}.dll" \
    "${QT6_INSTALL_PREFIX:+$QT6_INSTALL_PREFIX/bin/libgcc_s_${MINGW_GCC_SUFFIX}.dll}"; do
    [ -n "$cand" ] && [ -f "$cand" ] && { libgcc_src="$cand"; break; }
done
[ -n "$libgcc_src" ] || { echo "deploy-windows: FATAL: libgcc_s_${MINGW_GCC_SUFFIX}.dll not found" >&2; exit 1; }
cp -a "$libgcc_src" "${DIST}/"


# Transitive closure через objdump -p
declare -A seen=()
queue=("${DIST}/${APP_NAME_BIN}.exe")
for f in "${DIST}"/*.dll; do [ -f "$f" ] && queue+=("$f"); done
while [ ${#queue[@]} -gt 0 ]; do
    f="${queue[0]}"; queue=("${queue[@]:1}")
    base="$(basename "$f")"
    [ -n "${seen[$base]:-}" ] && continue
    seen[$base]=1
    deps="$(${MINGW_TRIPLET}-objdump -p "$f" 2>/dev/null | awk '/DLL Name:/{print $3}')"
    for dep in $deps; do
        [ -n "${seen[$dep]:-}" ] && continue
        if [ -f "${DIST}/$dep" ]; then
            queue+=("${DIST}/$dep")
            continue
        fi
        src=""
        for cand in \
            "${SYSROOT}/bin/$dep" \
            "${SYSROOT}/lib/$dep" \
            "/usr/lib/gcc/${MINGW_TRIPLET}/13-posix/$dep" \
            "/usr/lib/gcc/${MINGW_TRIPLET}/12-posix/$dep" \
            "/usr/lib/gcc/${MINGW_TRIPLET}/13-win32/$dep" \
            "/usr/lib/gcc/${MINGW_TRIPLET}/12-win32/$dep"; do
            [ -f "$cand" ] && { src="$cand"; break; }
        done
        if [ -z "$src" ]; then
            case "$dep" in
                KERNEL32.dll|USER32.dll|GDI32.dll|ADVAPI32.dll|SHELL32.dll|ole32.dll|OLEAUT32.dll|WS2_32.dll|WINMM.dll|IMM32.dll|UxTheme.dll|dwmapi.dll|D3D11.dll|D3D9.dll|OPENGL32.dll|GLU32.dll|COMCTL32.dll|COMDLG32.dll|RPCRT4.dll|CRYPT32.dll|secur32.dll|bcrypt.dll|ncrypt.dll|IPHLPAPI.DLL|DNSAPI.dll|NETAPI32.dll|USERENV.dll|VERSION.dll|SHLWAPI.dll|MPR.dll|WINSPOOL.DRV|PSAPI.DLL|POWRPROF.dll|SETUPAPI.dll|CFGMGR32.dll|WTSAPI32.dll|MSVCRT.dll|api-ms-win-*.dll|ext-ms-*.dll)
                    continue ;;
            esac
            echo "deploy-windows: NOTE: $dep (from $base) not found — likely system DLL" >&2
            continue
        fi
        if ! ${MINGW_TRIPLET}-objdump -f "$src" 2>/dev/null | grep -q "${MINGW_PEI}"; then
            echo "deploy-windows: FATAL: $src is not ${MINGW_PEI}" >&2
            ${MINGW_TRIPLET}-objdump -f "$src" >&2
            exit 1
        fi
        cp -a "$src" "${DIST}/"
        queue+=("${DIST}/$dep")
    done
done

# ── appinfo в DK (для консистентности с linux-DK и на случай WSL) ──
_prefix="${CORE_INSTALL_BASE:-/opt/rv}/qt${QT_VERSION_MAJOR}/${V}"
if [ -f "${_prefix}/appinfo.env" ]; then
    cp -f "${_prefix}/appinfo.env" "${DK_ROOT}/appinfo.env"
    cp -f "${_prefix}/appinfo.env" "${DK_ROOT}/appinfo"
fi

# Sanity
_err=0
test -f "${DIST}/${APP_NAME_BIN}.exe" || { echo "deploy-windows: FATAL: ${APP_NAME_BIN}.exe missing" >&2; _err=1; }
test -f "${DIST}/libcore-lib.dll"      || { echo "deploy-windows: FATAL: libcore-lib.dll missing" >&2; _err=1; }
test -f "${DIST}/platforms/qwindows.dll" || { echo "deploy-windows: FATAL: platforms/qwindows.dll missing" >&2; _err=1; }
test -f "${DIST}/libwinpthread-1.dll"  || { echo "deploy-windows: FATAL: libwinpthread-1.dll missing" >&2; _err=1; }
[ "$_err" = "0" ] || exit 1

echo "deploy-windows: ${DIST_NAME} (Qt${QT_VERSION_MAJOR}, ${MINGW_TRIPLET}): $(ls -1 "${DIST}"/*.dll | wc -l) dll"