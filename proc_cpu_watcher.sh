#!/usr/bin/env bash

# ============================================
# proc_cpu_watcher.sh - мониторинг нагрузки на CPU
# Отслеживает процессы, потребляющие аномально много CPU
# ============================================

# === Конфигурация (позже вынести в файл) ===
CPU_WARN_THRESHOLD=2     # первый порог (предупреждение) в %
CPU_KILL_THRESHOLD=4      # второй порог (рекомендация убить) в %
IGNORE_COMMS="systemd,kthreadd,rcu_sched,gnome-shell,gnome-terminal-server,Xorg"

# === Логирование (обёртки над logger) ===
LOG_TAG="proc_cpu_watcher"

log_info() {
    logger -t "$LOG_TAG" -p user.info "[info]: $1"
}

log_warn() {
    logger -t "$LOG_TAG" -p user.warning "[warn]: $1"
}

log_error() {
    logger -t "$LOG_TAG" -p user.err "[err]: $1"
}

# === Проверка, нужно ли игнорировать процесс ===
should_ignore() {
    local comm="$1"
    echo "$IGNORE_COMMS" | grep -q "$comm"
    return $?
}

# === Получение нагрузки на CPU (аналог top) ===
# Возвращает процент CPU для каждого процесса
get_cpu_usage() {
    # Используем ps с выводом %cpu (уже готовый процент)
    # %cpu — это CPU usage за последние секунды (аналог top)
    # ps -eo pid,comm,%cpu --no-headers 2>/dev/null
	ps -e -o pid,%cpu,comm --sort=-%cpu --no-headers 2>/dev/null | head -20
}

# === Проверка одного процесса ===
check_process_cpu() {
    local pid="$1"
    local comm="$2"
    local cpu_percent="$3"
    
    # Округляем до целого (убираем дробную часть)
    local cpu_int=${cpu_percent%.*}
    
    
    log_info "проверяем процесс в $comm (PID $pid) потребляет ${cpu_percent}% CPU"
    
    # KILL порог — критично
    if [[ $cpu_int -ge $CPU_KILL_THRESHOLD ]]; then
        log_error "КРИТИЧЕСКИ: Процесс $comm (PID $pid) потребляет ${cpu_percent}% CPU (порог: ${CPU_KILL_THRESHOLD}%) — РЕКОМЕНДУЕТСЯ ЗАВЕРШИТЬ (kill $pid) для предотвращения перегрева"
        return 0
    fi
    
    # WARN порог — предупреждение
    if [[ $cpu_int -ge $CPU_WARN_THRESHOLD ]] && [[ $cpu_int -lt $CPU_KILL_THRESHOLD ]]; then
        log_warn "Процесс $comm (PID $pid) потребляет ${cpu_percent}% CPU (порог: ${CPU_WARN_THRESHOLD}%) — возможна утечка или бесконечный цикл"
        return 0
    fi
    
    return 1
}

# === Основная проверка ===
check_all_processes() {
    local found_anomaly=0
    local cpu_output
    
    cpu_output=$(get_cpu_usage)

    if [[ -z "$cpu_output" ]]; then
        log_error "Не удалось получить данные о CPU"
        return 1
    fi
    
    while IFS= read -r line; do
        # Убираем пробелы в начале
        line=$(echo "$line" | sed 's/^[ \t]*//')

        local pid=$(echo "$line" | awk '{print $1}')
        local comm=$(echo "$line" | awk '{print $3}')
        local cpu_percent=$(echo "$line" | awk '{print $2}')

        # Проверяем валидность PID
        if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
        	log_info "неверный вывод pid=$pid"
            continue
        fi

        # Игнорируем процессы с нулевой нагрузкой
        if (( $(echo "$cpu_percent < 1.0" | bc -l 2>/dev/null) )); then
            continue
        fi
        
        # Игнорируем системные процессы
        if should_ignore "$comm"; then
        	log_info "процесс $comm с cpu=$cpu_percent% проигнорирован как помеченный в игнор-листе"
            continue
        fi

        if check_process_cpu "$pid" "$comm" "$cpu_percent"; then
            ((found_anomaly++))
        fi
        
    done <<< "$cpu_output"
   log_info "Аномалий CPU обнаружено: $found_anomaly"

}

check_all_processes
