#!/bin/sh
# CoreCI/scripts/bundle-linux-deps.sh — offline-зависимости (mosquitto/dlt) + install.sh + tar.gz.
#
# Env:
#   DEB_ARCH      amd64 | arm64 | armhf
#   DEPLOY_DIR    /deploy (appinfo.env + <app>_<ver>_<arch>.deb от make-deb.sh)
#   BUNDLE_DIR    /app (где создать <app>_<ver>/ и tar.gz)
set -eu

: "${DEB_ARCH:?bundle-linux-deps: DEB_ARCH is required}"
: "${DEPLOY_DIR:?bundle-linux-deps: DEPLOY_DIR is required}"
BUNDLE_DIR="${BUNDLE_DIR:-/app}"

. "${DEPLOY_DIR}/appinfo.env"

# ── URL пакетов по архитектурам ──────────────────────────────────────
case "${DEB_ARCH}" in
    amd64)
        DLT_URL="https://ftp.debian.org/debian/pool/main/d/dlt-daemon/libdlt2_2.18.8-6_amd64.deb"
        LIBMOSQUITTO_URL="https://ftp.debian.org/debian/pool/main/m/mosquitto/libmosquitto1_2.0.11-1.2+deb12u2_amd64.deb"
        MOSQUITTO_URL="https://ftp.debian.org/debian/pool/main/m/mosquitto/mosquitto_2.0.11-1.2+deb12u2_amd64.deb"
        ;;
    arm64)
        DLT_URL="https://ftp.debian.org/debian/pool/main/d/dlt-daemon/libdlt2_2.18.8-6_arm64.deb"
        LIBMOSQUITTO_URL="https://ftp.debian.org/debian/pool/main/m/mosquitto/libmosquitto1_2.0.11-1.2+deb12u2_arm64.deb"
        MOSQUITTO_URL="https://ftp.debian.org/debian/pool/main/m/mosquitto/mosquitto_2.0.11-1.2+deb12u2_arm64.deb"
        ;;
    armhf)
        DLT_URL="https://ftp.debian.org/debian/pool/main/d/dlt-daemon/libdlt2_2.18.8-6_armhf.deb"
        LIBMOSQUITTO_URL="https://ftp.debian.org/debian/pool/main/m/mosquitto/libmosquitto1_2.0.11-1.2+deb12u2_armhf.deb"
        MOSQUITTO_URL="https://ftp.debian.org/debian/pool/main/m/mosquitto/mosquitto_2.0.11-1.2+deb12u2_armhf.deb"
        ;;
    *)
        echo "bundle-linux-deps: unsupported DEB_ARCH=${DEB_ARCH}" >&2
        exit 1
        ;;
esac

B="${BUNDLE_DIR}/${APP_NAME_EN}_${APP_VERSION}"
mkdir -p "$B/deps"

# Заглушки TODO* пропускаем с предупреждением (arm собирается без offline-deps,
# mosquitto всё равно ставится через apt-get в install.sh).
fetch() {
    case "$1" in
        TODO*|"")
            echo "bundle-linux-deps: NOTE: skip $2 — URL-заглушка для ${DEB_ARCH}" >&2
            return 0
            ;;
    esac
    wget -qO "$2" "$1"
}

fetch "$DLT_URL"          "$B/deps/libdlt2_${DEB_ARCH}.deb"
fetch "$LIBMOSQUITTO_URL" "$B/deps/libmosquitto1_${DEB_ARCH}.deb"
fetch "$MOSQUITTO_URL"    "$B/deps/mosquitto_${DEB_ARCH}.deb"

cp "${DEPLOY_DIR}/${APP_NAME_EN}_${APP_VERSION}_${DEB_ARCH}.deb" "$B/"

# ── install.sh ───────────────────────────────────────────────────────
cat > "$B/install.sh" <<INSTALL
#!/bin/bash
set -e
echo "Установка системных зависимостей..."
sudo apt-get update
sudo apt-get install -y libmd4c0 libxerces-c3.2 libdouble-conversion3 libpcre2-16-0 libwrap0 mosquitto
echo "Установка ${APP_NAME_RU} и MQTT-брокера..."
sudo dpkg -i ./deps/*.deb || true
sudo dpkg -i ./${APP_NAME_EN}_${APP_VERSION}_${DEB_ARCH}.deb || true
sudo apt-get -f install -y || true
echo "Установка завершена."
INSTALL
chmod +x "$B/install.sh"

cd "$BUNDLE_DIR"
tar czf "${APP_NAME_EN}_${APP_VERSION}.tar.gz" "${APP_NAME_EN}_${APP_VERSION}"
echo "bundle-linux-deps: ${BUNDLE_DIR}/${APP_NAME_EN}_${APP_VERSION}.tar.gz"