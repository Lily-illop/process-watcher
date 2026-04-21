#!/usr/bin/env bash

# ============================================
# proc_watcher.sh - простая проверка долгоживущих процессов
# Пока умеет: проверять время жизни, выводить эхо-уведомления
# ============================================

# Конфиг (пока просто переменные)
MAX_AGE_HOURS=100
IGNORE_COMMS="systemd,kthreadd,rcu_sched"

# Заглушка для будущего конфига
load_config() {
	echo "[ЗАГЛУШКА] Здесь будет загрузка конфига из файла, пока предустановленно кол-во часов=100 и игнор-лист=systemd,kthreadd,rcu_sched"
}

# Заглушка для будущих уведомлений
send_notification() {
	local name="$1"
	local pid="$2"
	local age="$3"

	# Пока просто эхо в консоль с понятным маркером
	echo "🔔 [УВЕДОМЛЕНИЕ] Процесс $name (PID $pid) живёт ${age}ч (порог: ${MAX_AGE_HOURS}ч)"
}

# Проверка, нужно ли игнорировать процесс
should_ignore() {
    local name="$1"
    echo "$IGNORE_COMMS" | grep -q "$name"
}

# Основная проверка (заглушка)
check_processes() {
    echo "Начало проверки.."
    
    # ВРЕМЕННО: симулируем найденный процесс
    # Потом заменим на реальный ps
    local fake_pid=12345
    local fake_name="sleep"
    local fake_age_hours=150
    
    if should_ignore "$fake_name"; then
        echo "   (игнорирую $fake_name)"
    else
        if (( $(echo "$fake_age_hours > $MAX_AGE_HOURS" | bc -l) )); then
            send_notification "$fake_name" "$fake_pid" "$fake_age_hours"
        fi
    fi
}

# Точка входа
main() {
    echo "=== Proc Watcher (простая версия) ==="
    echo "Порог: ${MAX_AGE_HOURS} часов"
    load_config
    check_processes
    echo "=== Готово ==="
}

main

