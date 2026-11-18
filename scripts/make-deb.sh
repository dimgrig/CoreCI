#!/bin/sh
# CoreCI/scripts/make-deb.sh — .deb из DistributionKit.
#
# Env:
#   DIST_NAME        ModbusClientDistributionKit / SaksRenovaDistributionKit
#   DEB_ARCH         amd64 | arm64 | armhf
#   DEPLOY_DIR       /deploy (где appinfo.env)
#   QT_VERSION_MAJOR 5|6
#   ICON_SRC         /path/to/icon.ico (конвертируется в .png)
#   EXTRA_DEPENDS    "libssl3, libicu72" (опц.)
set -eu

: "${DIST_NAME:?}"
: "${DEB_ARCH:?}"
: "${QT_VERSION_MAJOR:?}"

DEPLOY_DIR="${DEPLOY_DIR:-/deploy}"
DIST="${DEPLOY_DIR}/${DIST_NAME}"
PKG_DIR=/deb-package

[ -d "$DIST" ] || { echo "make-deb: FATAL: $DIST not found" >&2; exit 1; }
. "${DEPLOY_DIR}/appinfo.env"

# Иконка
if [ ! -f "${DEPLOY_DIR}/${ICON_NAME}.png" ] && [ -n "${ICON_SRC:-}" ] && [ -f "$ICON_SRC" ]; then
    if command -v convert >/dev/null 2>&1; then
        convert "${ICON_SRC}[0]" -resize 256x256 "${DEPLOY_DIR}/${ICON_NAME}.png"
    fi
fi

mkdir -p "$PKG_DIR/DEBIAN" "$PKG_DIR/opt/${APP_NAME_EN}"
cp -r "$DIST"/* "$PKG_DIR/opt/${APP_NAME_EN}/"
[ -f "${DEPLOY_DIR}/${ICON_NAME}.png" ] && \
    cp "${DEPLOY_DIR}/${ICON_NAME}.png" "$PKG_DIR/opt/${APP_NAME_EN}/"

case "${QT_VERSION_MAJOR}" in
    6) BASE_DEPENDS="libc6 (>= 2.36), libstdc++6, libharfbuzz0b, libfontconfig1, libfreetype6, libglib2.0-0, libgraphite2-3, libzstd1, libpcre2-16-0, libssl3, libxcb1, libx11-6, libxcb-cursor0, libxkbcommon0, libxkbcommon-x11-0, libgl1" ;;
    *) BASE_DEPENDS="libc6, libstdc++6" ;;
esac
DEPENDS="${BASE_DEPENDS}${EXTRA_DEPENDS:+, ${EXTRA_DEPENDS}}"

cat > "$PKG_DIR/DEBIAN/control" <<CONTROL
Package: ${APP_NAME_EN}
Version: ${APP_VERSION}
Section: ${SECTION:-utils}
Priority: optional
Architecture: ${DEB_ARCH}
Maintainer: ${MAINTAINER:-Unknown}
Description: ${APP_NAME_RU}
Depends: ${DEPENDS}
CONTROL

cat > "$PKG_DIR/DEBIAN/postinst" <<POSTINST
#!/bin/sh
set -e
mkdir -p /usr/share/applications
cat > /usr/share/applications/${APP_NAME_EN}.desktop <<DESKTOP
[Desktop Entry]
Type=Application
Name=${APP_NAME_RU}
Comment=${APP_NAME_RU}
Exec=/opt/${APP_NAME_EN}/bin/${APP_NAME_BIN}
Icon=/opt/${APP_NAME_EN}/${ICON_NAME}.png
Terminal=false
Categories=Network;Utility;
DESKTOP
mkdir -p /usr/share/icons/hicolor/256x256/apps
[ -f /opt/${APP_NAME_EN}/${ICON_NAME}.png ] && \
    cp /opt/${APP_NAME_EN}/${ICON_NAME}.png /usr/share/icons/hicolor/256x256/apps/${ICON_NAME}.png
ln -sf /opt/${APP_NAME_EN}/bin/${APP_NAME_BIN} /usr/local/bin/${APP_NAME_BIN}
exit 0
POSTINST
chmod +x "$PKG_DIR/DEBIAN/postinst"

DEB_OUT="${DEPLOY_DIR}/${APP_NAME_EN}_${APP_VERSION}_${DEB_ARCH}.deb"
dpkg-deb --build "$PKG_DIR" "$DEB_OUT"
test -f "$DEB_OUT"

if dpkg-deb -c "$DEB_OUT" | grep -q '/libc\.so'; then
    echo "make-deb: FATAL: glibc leaked into .deb" >&2
    exit 1
fi

echo "make-deb: ${DEB_OUT}: $(du -h "$DEB_OUT" | cut -f1)"