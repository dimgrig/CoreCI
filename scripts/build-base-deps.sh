#!/bin/bash
# CoreCI/scripts/build-base-deps.sh — сборка base-deps образов.
#
# Исторически: Core/docker-build-base-deps.sh.
# Запуск: из любого места; скрипт сам находит корень CoreCI/.

set -e
cd "$(dirname "$0")/.." || exit   # → ~/QtProjects/CoreCI/

: <<'COMMENT'
Примеры:
./scripts/build-base-deps.sh
BUILD_INNOSETUP=1 ./scripts/build-base-deps.sh
COMMENT

# ── 0. Pull qt68 (собирается вручную через GitHub Actions) ──
QT68_IMAGE=ghcr.io/dimgrig/qt68-bookworm-arm64:6.8.5
echo "=== qt68: pull ${QT68_IMAGE} ==="
docker pull --platform linux/arm64 "${QT68_IMAGE}" || {
    echo "ERROR: cannot pull ${QT68_IMAGE}" >&2
    echo "" >&2
    echo "Build it once via GitHub Actions in dimgrig/CoreCI:" >&2
    echo "  Actions → 'Build qt68-bookworm-arm64 (manual)' → Run workflow" >&2
    exit 1
}

echo "=== Qt5 base images ==="
echo "=== base-deps-linux:latest ==="
docker build -t base-deps-linux:latest -f docker/Dockerfile.base-deps-linux .
echo "=== base-deps-win:latest ==="
docker build -t base-deps-win:latest -f docker/Dockerfile.base-deps-win .
echo "=== base-deps-arm64:latest ==="
docker buildx build --platform linux/arm64 -t base-deps-arm64:latest -f docker/Dockerfile.base-deps-arm64 .
echo "=== base-deps-armv7:latest ==="
docker buildx build --platform linux/arm/v7 -t base-deps-armv7:latest -f docker/Dockerfile.base-deps-armv7 .

echo "=== Qt6 base images ==="
echo "=== base-deps-linux-qt6:latest ==="
docker build -t base-deps-linux-qt6:latest -f docker/Dockerfile.base-deps-linux-qt6 .
echo "=== base-deps-win64-qt6:latest ==="
docker build -t base-deps-win64-qt6:latest -f docker/Dockerfile.base-deps-win64-qt6 .

echo "=== base-deps-arm64-qt6:latest ==="
docker buildx build --platform linux/arm64 \
    --build-arg QT68_IMAGE="${QT68_IMAGE}" \
    -t base-deps-arm64-qt6:latest \
    -f docker/Dockerfile.base-deps-arm64-qt6 .

if [ "${BUILD_ASTRA:-0}" = "1" ]; then
    echo "=== base-deps-astra:latest ==="
    echo "NOTE: Dockerfile.base-deps-astra остаётся в Core/ (TODO: вынести в CoreCI)."
    echo "      Этот образ здесь не собирается." >&2
    exit 1
fi

if [ "${BUILD_INNOSETUP:-0}" = "1" ]; then
    echo "=== innosetup-base:latest ==="
    docker build -t innosetup-base:latest -f docker/Dockerfile.innosetup-base .
fi

echo "=== Готово ==="