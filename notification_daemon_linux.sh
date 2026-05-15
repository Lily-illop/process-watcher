#!/usr/bin/env bash

# ============================================
# notification_daemon.sh - отправляет уведомления из логов
# Следит за journalctl и показывает всплывающие уведомления
# ============================================

# Конфигурация
LOG_TAG="proc_watcher"
MIN_LEVEL="warning"  # info, warning, error
LAST_SEEN_FILE="/tmp/proc_watcher_last_time"

# Функция отправки уведомления (платформозависимая часть)
send_notification() {
    local title="$1"
    local message="$2"
    
    # Определяем ОС и окружение
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [[ -n "$DISPLAY" ]] && command -v notify-send >/dev/null 2>&1; then
            notify-send -u normal "$title" "$message" 2>/dev/null || true
        elif command -v zenity >/dev/null 2>&1; then
            zenity --notification --text="$title: $message" 2>/dev/null || true
        else
            echo "[$title] $message"
        fi
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
        
    elif [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]]; then
        # Windows (Git Bash)
        powershell -Command "& {Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('$message', '$title')}" 2>/dev/null || true
    else
        echo "[$title] $message"
    fi
}

# Получить время последнего просмотра
get_last_time() {
    if [[ -f "$LAST_SEEN_FILE" ]]; then
        cat "$LAST_SEEN_FILE"
    else
        # По умолчанию: последние 5 минут
        date --date='5 minutes ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || \
        date -v-5M '+%Y-%m-%d %H:%M:%S' 2>/dev/null  # macOS
    fi
}

# Основной цикл наблюдения
watch_logs() {
    local last_time=$(get_last_time)
    local current_time="$last_time"
    
    # Читаем новые записи из journalctl (или syslog fallback)
    if command -v journalctl >/dev/null 2>&1; then
        # systemd — используем journalctl
        journalctl -t "$LOG_TAG" --since="$last_time" -o cat -p "$MIN_LEVEL" 2>/dev/null | while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                send_notification "Proc Watcher" "$line"
                echo "🔔 $line"
            fi
            current_time=$(date '+%Y-%m-%d %H:%M:%S')
        done
    elif [[ -f /var/log/syslog ]]; then
        # fallback для систем без systemd
        tail -n 50 /var/log/syslog | grep "$LOG_TAG" | grep -E "(WARNING|ERROR)" | while IFS= read -r line; do
            send_notification "Proc Watcher" "$line"
        done
    fi
    
    # Сохраняем время последнего просмотра
    echo "$current_time" > "$LAST_SEEN_FILE"
}

# Демонизация (опционально)
run_daemon() {
    local interval=${1:-10}  # проверка каждые 10 секунд по умолчанию
    
    echo "=== Notification Daemon запущен ==="
    echo "Слежу за тегом: $LOG_TAG"
    echo "Уровень: $MIN_LEVEL"
    echo "Интервал: ${interval}с"
    
    while true; do
        watch_logs
        sleep "$interval"
    done
}

# Парсинг аргументов
case "$1" in
    --interval)
        run_daemon "$2"
        ;;
    --once)
        watch_logs
        ;;
    --level)
        MIN_LEVEL="$2"
        watch_logs
        ;;
    --help)
        echo "Использование: $0 [ОПЦИИ]"
        echo "  --interval N   Запустить как демон с интервалом N секунд"
        echo "  --once         Однократная проверка"
        echo "  --level LVL    Уровень логов (info/warning/error)"
        echo "  --help         Показать справку"
        ;;
    *)
        run_daemon 10
        ;;
esac
