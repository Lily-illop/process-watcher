#!/usr/bin/env bash

# ============================================
# proc_watcher.sh - простая проверка долгоживущих процессов
# Пока умеет: проверять время жизни, выводить эхо-уведомления
# ============================================

# Конфиг (пока просто переменные)
MAX_AGE_HOURS=9
IGNORE_COMMS="systemd,kthreadd,rcu_sched"

# Заглушка для будущего конфига
load_config() {
	echo "[ЗАГЛУШКА] Здесь будет загрузка конфига из файла, пока предустановленно кол-во часов=$MAX_AGE_HOURS и игнор-лист=$IGNORE_COMMS"
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

# Основная проверка по времени жизни процессов
check_processes() {
    echo "Начало проверки.."
    
    # Проверяем, существует ли команда ps
    if ! command -v ps &>/dev/null; then
        echo "❌ Ошибка: команда 'ps' не найдена в системе" >&2
        return 1
    fi
    
    
    local count_anomaly=0
    local ps_output
    
    # ps - команда для вывода информации о процессах
    #   -e     : выбрать ВСЕ процессы (включая не принадлежащие текущему пользователю)
    #   -o     : задать пользовательский формат вывода
    #   pid,comm,etime : какие поля выводить
    #     comm  : Command name, имя исполняемого файла (без аргументов)
    #     etime : Elapsed time, время жизни процесса в формате [[DD-]hh:]mm:ss
    #   --no-headers : не печатать строку с названиями столбцов
    #   2>/dev/null   : перенаправить stderr (ошибки) в "чёрную дыру"
    #                   чтобы не видеть предупреждения о процессах,
    #                   которые завершились между сканированием и чтением
    ps_output=$(ps -eo pid,comm,etime --no-headers 2>/dev/null)
    
    # Проверка: если ps ничего не вернул (ошибка или нет процессов)
    if [[ -z "$ps_output" ]]; then
        echo "❌ Ошибка: не удалось получить список процессов">&2
        return 1
    fi
    
    
        # Читаем вывод ps построчно
    # <<< "$ps_output" — это "here-string", передаёт содержимое переменной
    # как стандартный ввод для цикла while
    while IFS= read -r line; do
        # IFS=  : временно отключаем разделение по пробелам,
        #         чтобы не обрезать пробелы в начале строки
        # read -r : читать строку буквально (raw), не интерпретируя \ как экранирование
        
        # Убираем пробелы и табуляции в начале строки
        line=$(echo "$line" | sed 's/^[ \t]*//')
        
        local pid=$(echo "$line" | awk '{print $1}')  # Извлекаем PID (первое поле до пробела), awk '{print $1}'  : берёт первое слово в строке
        local comm=$(echo "$line" | awk '{print $2}')  # Извлекаем имя процесса (второе поле)
        # Извлекаем время жизни (последнее поле) $NF - специальная переменная awk, означающая "Number of Fields", т.е. последнее поле в строке
        local etime_str=$(echo "$line" | awk '{print $NF}')
        
        # Проверяем, что PID состоит только из цифр
        if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
            continue  # пропускаем строки, где PID не число (например, заголовки)
        fi
        
        # Проверяем, нужно ли игнорировать этот процесс
        if should_ignore "$comm"; then
        	echo ""
            continue  # пропускаем, пользователь не хочет видеть уведомления о нём
        fi
        
        # === Парсим время жизни в секунды ===
        # etime может быть в нескольких форматах:
        #   "1-02:03:04"  : 1 день, 2 часа, 3 минуты, 4 секунды
        #   "02:03:04"    : 2 часа, 3 минуты, 4 секунды
        #   "03:04"       : 3 минуты, 4 секунды
        #   "123"         : 123 секунды
        local age_sec=0
        
        # Формат с днями: "1-02:03:04"
        if [[ "$etime_str" =~ ^([0-9]+)-([0-9]{2}):([0-9]{2}):([0-9]{2})$ ]]; then
            local days=${BASH_REMATCH[1]}      # первая группа
            local hours=${BASH_REMATCH[2]}     # вторая группа
            local minutes=${BASH_REMATCH[3]}   # третья группа
            local seconds=${BASH_REMATCH[4]}   # четвёртая группа
            # 86400 = 24 * 3600 (секунд в дне)
            age_sec=$((10#$days*86400 + 10#$hours*3600 + 10#$minutes*60 + 10#$seconds))
        
        # Формат с часами: "02:03:04"
        elif [[ "$etime_str" =~ ^([0-9]{2}):([0-9]{2}):([0-9]{2})$ ]]; then
            local hours=${BASH_REMATCH[1]}
            local minutes=${BASH_REMATCH[2]}
            local seconds=${BASH_REMATCH[3]}
            age_sec=$((10#$hours*3600 + 10#$minutes*60 + 10#$seconds))
        
        # Формат с минутами: "03:04"
        elif [[ "$etime_str" =~ ^([0-9]{2}):([0-9]{2})$ ]]; then
            local minutes=${BASH_REMATCH[1]}
            local seconds=${BASH_REMATCH[2]}
            age_sec=$((10#$minutes*60 + 10#$seconds))
        
        # Формат без двоеточий (только секунды): "123"
        elif [[ "$etime_str" =~ ^[0-9]+$ ]]; then
            age_sec=$((etime_str))
        
        else
        	echo "⚠️ Предупреждение: неизвестный формат etime '$etime_str' — пропускаем процесс" >&2
            # Такое может случиться для процессов-зомби или с очень странным etime
            continue
        fi
        
        # Переводим секунды в часы
        local age_hours=$(echo "$age_sec / 3600" | bc 2>/dev/null)
        
        # Сравниваем с порогом
        # bc -l : сравниваем дробные числа (bash сам не умеет)
        # || true : подстраховка на случай ошибки bc
        if (( $(echo "$age_hours > $MAX_AGE_HOURS" | bc -l 2>/dev/null || echo 0) )); then
            send_notification "$comm" "$pid" "$age_hours"
            count_anomaly=$((count_anomaly + 1))
        fi
        
    done <<< "$ps_output"   # конец цикла while; here-string с данными ps
    
    # Итоговый отчёт
    if [[ $count_anomaly -eq 0 ]]; then
        # wc -l : подсчёт строк (word count, lines)
        local process_count=$(echo "$ps_output" | wc -l)
        echo "✅ Аномалий не обнаружено. Проверено процессов: $process_count"
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

