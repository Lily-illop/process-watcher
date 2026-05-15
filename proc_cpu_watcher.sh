#!/usr/bin/env bash

# ============================================
# proc_cpu_watcher.sh - мониторинг нагрузки на CPU
# Отслеживает процессы, потребляющие аномально много CPU
# ============================================

# Получаем путь к директории скрипта
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Подключаем библиотеку и конфиг
source "$SCRIPT_DIR/lib.sh"
load_config "$SCRIPT_DIR/config.env"

# === Настройки (с значениями по умолчанию) ===
CPU_WARN_THRESHOLD=${CPU_WARN_THRESHOLD:-50} # первый порог (предупреждение) в %
CPU_KILL_THRESHOLD=${CPU_KILL_THRESHOLD:-90} # второй порог (рекомендация убить) в %
IGNORE_COMMS=${IGNORE_COMMS:-"systemd,kthreadd,rcu_sched,gnome-shell,gnome-terminal-server,Xorg"}

log_debug "Значения установленны. Первый порог $CPU_WARN_THRESHOLD. Второй порог $CPU_KILL_THRESHOLD. И игнор-лист: $IGNORE_COMMS"

# === Получение нагрузки на CPU (аналог top) ===
# Возвращает процент CPU для каждого процесса
get_cpu_usage() {
    # Используем ps с выводом %cpu (уже готовый процент)
    # %cpu — это CPU usage за последние секунды (аналог top)
    # ps -eo pid,comm,%cpu --no-headers 2>/dev/null
	ps -e -o pid,%cpu,cmd,comm --sort=-%cpu --no-headers 2>/dev/null | head -20
}

# === Проверка одного процесса ===
check_process_cpu() {
    local pid="$1"
    local comm="$2"
    local cpu_percent="$3"
    
    # Округляем до целого (убираем дробную часть)
    local cpu_int=${cpu_percent%.*}
    
    
    log_debug "проверяем процесс в $comm (PID $pid) потребляет ${cpu_percent}% CPU"
    
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
		log_debug "рабоатем со строкой на входе(после удаления пробеллов): $line"
        local pid=$(echo "$line" | awk '{print $1}')
        local cpu_percent=$(echo "$line" | awk '{print $2}')
		# Берём всё, начиная с 3-го поля, и заменяем пробелы на _
		local comm=$(echo "$line" | cut -d' ' -f4-)
		log_debug "парсинг имени процесса получаем $comm"	
        # Проверяем валидность PID
        if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
        	log_debug "неверный вывод pid=$pid в строке $line"
            continue
        fi

        # Игнорируем процессы с нулевой нагрузкой
        if (( $(echo "$cpu_percent < 1.0" | bc -l 2>/dev/null) )); then
            log_debug "игнорируем $cpu_percent < 1.0 в процессе $line "
            continue
        fi
        
        # Игнорируем системные процессы
        if should_ignore "$comm"; then
        	log_debug "процесс $comm с cpu=$cpu_percent% проигнорирован как помеченный в игнор-листе"
            continue
        fi

        if check_process_cpu "$pid" "$comm" "$cpu_percent"; then
            ((found_anomaly++))
        fi
        
    done <<< "$cpu_output"
   log_info "Аномалий CPU обнаружено: $found_anomaly"

}


# Точка входа
main() {
    log_info "=== Proc Watcher CPU anomaly==="
    log_info "Пороги: $CPU_WARN_THRESHOLD % -warn. $CPU_KILL_THRESHOLD % - error."
    check_all_processes
    log_info "=== Готово ==="
}

main
