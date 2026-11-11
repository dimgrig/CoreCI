# CoreCI

Общая инфраструктура для проектов на Core:
Core, modbus-client, modbus-server, saks.

Используется как git submodule (`.ci`) во всех проектах.
Exact-pin (`git checkout vX.Y.Z`) — обязателен для воспроизводимости.

## Состав

- `docker/` — base-deps (linux/win/arm64/armv7), qt68-arm64, innosetup
- `scripts/` — сборка base-deps образов
- `cmake/` — CreateLatestLink (перенос из Core)
- `qmake/` — qmake-target-platform.pri, qmake-destination-path.pri

## Публикуемые образы (ghcr)

Теги не меняются от переезда — потребители (`BASE_DEPS_IMAGE` в compose) продолжают работать:

- `ghcr.io/dimgrig/core-base-deps-linux:qt5-bookworm`
- `ghcr.io/dimgrig/core-base-deps-linux:qt6-bookworm`
- `ghcr.io/dimgrig/core-base-deps-win:qt5-mingw`
- `ghcr.io/dimgrig/core-base-deps-win64:qt6-mingw`
- `ghcr.io/dimgrig/core-base-deps-arm64:qt5-bookworm`
- `ghcr.io/dimgrig/core-base-deps-arm64:qt6-bookworm-aqt`
- `ghcr.io/dimgrig/core-base-deps-armv7:qt5-bullseye`
- `ghcr.io/dimgrig/innosetup-base:latest`
- `ghcr.io/dimgrig/qt68-bookworm-arm64:6.8.5`

## Подключение в проект

```bash
git submodule add https://github.com/dimgrig/CoreCI.git .ci
cd .ci && git checkout v0.1.0 && cd ..
