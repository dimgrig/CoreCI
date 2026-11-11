#!/usr/bin/env bash
# ============================================================================
# CoreCI/scripts/detect-export-mode.sh — общий детектор dev/ci.
#
# Использование:
#   source "$(...)/.ci/scripts/detect-export-mode.sh"
#   detect_export_mode || exit 1   # выставляет EXPORT_MODE=dev|ci
#
# Приоритет (от высшего к низшему):
#   1. EXPORT_MODE явно (dev|ci)                 — override
#   2. CI=true                                   — GHA / GitLab / Travis
#   3. DEPLOY_ROOT задан                         — пользователь явно сказал «dev»
#   4. $HOME/deploy существует                   — маркер dev-машины
#                                                  (переживает "rm -rf ~/deploy/core")
#   5. $HOME/deploy/core или $HOME/.local/core   — legacy-раскладки
#   6. fallback: ci
#
# Побочных эффектов нет: каталоги только читаются, ничего не создаётся.
# ============================================================================
detect_export_mode() {
    if [ -n "${EXPORT_MODE:-}" ]; then
        case "$EXPORT_MODE" in dev|ci) return 0 ;; esac
        echo "ERROR: EXPORT_MODE='$EXPORT_MODE' (dev|ci)" >&2
        return 1
    fi
    if [ "${CI:-}" = "true" ]; then EXPORT_MODE="ci"; return 0; fi
    if [ -n "${DEPLOY_ROOT:-}" ]; then EXPORT_MODE="dev"; return 0; fi
    if [ -n "${HOME:-}" ] && [ -d "$HOME/deploy" ]; then EXPORT_MODE="dev"; return 0; fi
    if [ -n "${HOME:-}" ] && { [ -d "$HOME/deploy/core" ] || [ -d "$HOME/.local/core" ]; }; then
        EXPORT_MODE="dev"; return 0
    fi
    EXPORT_MODE="ci"
}