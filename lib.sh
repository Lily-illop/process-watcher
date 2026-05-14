#!/usr/bin/env bash
# ============================================
# lib.sh - общие функции для всех скриптов
# ============================================

# Загрузка конфига
load_config() {
    local config_file="${1:-config.env}"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
        log_info "Конфиг загружен из $config_file"
    else
        log_warn "Файл с именем $config_file (конфиг) не найден, используются значения по умолчанию" >&2
    fi
}

# === Логирование ===
# Если LOG_TAG не задан, используем имя скрипта
if [[ -z "$LOG_TAG" ]]; then
    LOG_TAG=$(basename "$0" .sh)
fi

log_info() {
    logger -t "$LOG_TAG" -p user.info "[info]: $1"
}

log_warn() {
    logger -t "$LOG_TAG" -p user.warning "[warn]: $1"
}

log_error() {
    logger -t "$LOG_TAG" -p user.err "[err]: $1"
}

log_debug() {
    if [[ -n "$DEBUG" ]]; then
        logger -t "$LOG_TAG" -p user.debug "[debug]: $1"
    fi
}

# === Проверка, нужно ли игнорировать процесс ===
should_ignore() {
    local comm="$1"
    local ignore_list="$2"
    echo "$ignore_list" | grep -q "$comm"
    return $?
}
