#!/bin/sh
# CoreCI/scripts/make-innosetup.sh — setup.exe из DistributionKit.
#
# Env:
#   DEPLOY_DIR    где appinfo.env + DIST_NAME/ (результат deploy-windows.sh)
#   SETUP_DIR     где setup.iss шаблон (в него пишется setup_filled.iss)
set -eu

: "${DEPLOY_DIR:?}"
: "${SETUP_DIR:?}"

[ -f "${SETUP_DIR}/setup.iss" ] || { echo "make-innosetup: FATAL: ${SETUP_DIR}/setup.iss not found" >&2; exit 1; }
. "${DEPLOY_DIR}/appinfo.env"

DIST="${DEPLOY_DIR}/${DIST_KIT_NAME}"
[ -f "${DIST}/${APP_NAME_BIN}.exe" ] || { echo "make-innosetup: FATAL: ${DIST}/${APP_NAME_BIN}.exe not found" >&2; exit 1; }

sed -e "s|@APP_VERSION@|${APP_VERSION}|g" \
    -e "s|@APP_NAME_RU@|${APP_NAME_RU}|g" \
    -e "s|@APP_NAME_EN@|${APP_NAME_EN}|g" \
    -e "s|@APP_NAME_BIN@|${APP_NAME_BIN}|g" \
    -e "s|@ICON_NAME@|${ICON_NAME}|g" \
    -e "s|@DIST_KIT_NAME@|${DIST_KIT_NAME}|g" \
    "${SETUP_DIR}/setup.iss" > "${SETUP_DIR}/setup_filled.iss"

iscc "${SETUP_DIR}/setup_filled.iss"
ls -la "${SETUP_DIR}"/*.exe