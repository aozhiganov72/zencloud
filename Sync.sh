#!/bin/bash

CLOUDS=$(rclone listremotes)

if [ -z "$CLOUDS" ]; then
    zenity --error --text="Не настроено ни одного облака!\n\nСначала выполните:\nrclone config"
    exit 1
fi

CLOUDS=$(rclone listremotes 2>/dev/null | sed 's/://g' | tr '\n' '|' | sed 's/|$//')
[ -z "$CLOUDS" ] && zenity --error --text="Нет облаков! rclone config" && exit 1

CLOUD_REMOTE=$(zenity --forms --title="Выбор облака"\
    --text="Выберите облако" \
    --combo-values=$CLOUDS\
    --add-combo="Ваш выбор")
[ $? -ne 0 ] && exit 0

CLOUD_REMOTE="${CLOUD_REMOTE%:}"

MOUNT_POINT="$HOME/cloud_browse_${CLOUD_REMOTE}"
mkdir -p "$MOUNT_POINT"

echo "Монтируем $CLOUD_REMOTE для просмотра..."
rclone mount "$CLOUD_REMOTE:" "$MOUNT_POINT" --daemon --vfs-cache-mode minimal
sleep 2

if ! mountpoint -q "$MOUNT_POINT"; then
    zenity --error --text="Не удалось смонтировать $CLOUD_REMOTE!"
    exit 1
fi

CLOUD_FOLDER=$(zenity --file-selection \
    --directory \
    --title="Выберите папку в облаке $CLOUD_REMOTE" \
    --filename="$MOUNT_POINT/")

fusermount -u "$MOUNT_POINT" 2>/dev/null
rmdir "$MOUNT_POINT" 2>/dev/null

if [ $? -ne 0 ] || [ -z "$CLOUD_FOLDER" ]; then
    exit 0
fi

RELATIVE_PATH="${CLOUD_FOLDER#*/cloud_browse_${CLOUD_REMOTE}/}"
if [ "$RELATIVE_PATH" = "$CLOUD_FOLDER" ]; then
    RELATIVE_PATH=""
fi

if [ -z "$RELATIVE_PATH" ]; then
    CLOUD_PATH="$CLOUD_REMOTE:"
else
    CLOUD_PATH="$CLOUD_REMOTE:$RELATIVE_PATH"
fi

echo "Выбрана облачная папка: $CLOUD_PATH"

LOCAL_DIR=$(zenity --file-selection \
    --directory \
    --title="Выберите локальную папку" \
    --filename="$HOME/")

if [ $? -ne 0 ] || [ -z "$LOCAL_DIR" ]; then
    exit 0
fi

LOCAL_NAME=$(basename "$LOCAL_DIR")
CLOUD_NAME=$(basename "$CLOUD_PATH" 2>/dev/null || echo "корень облака")

INFO_TEXT="⚡ Будет выполнена синхронизация:\n\n"
INFO_TEXT+="📁 Локальная папка: $LOCAL_NAME\n"
INFO_TEXT+="📍 Путь: $LOCAL_DIR\n\n"
INFO_TEXT+="☁️ Облако: $CLOUD_REMOTE\n"
INFO_TEXT+="📂 Папка в облаке: $CLOUD_NAME\n"
INFO_TEXT+="📍 Путь: $CLOUD_PATH"

zenity --info \
    --title="Информация о синхронизации" \
    --text="$INFO_TEXT" \
    --width=500

SYNC_TYPE=$(zenity --list \
    --title="Выберите тип синхронизации" \
    --text="Как синхронизировать папки?" \
    --column="Тип" \
    --column="Описание" \
    "cloud_to_local" "Облако → Локально (ведущее облако)" \
    "local_to_cloud" "Локально → Облако (ведущая локальная)" \
    "two_way" "Двусторонняя (объединить изменения)" \
    "copy_new_only" "Только новые файлы (без удаления)" \
    "mirror_cloud" "Зеркало облака (точная копия)" \
    "mirror_local" "Зеркало локальной (точная копия)"\
    --width=400\
    --height=300)

if [ $? -ne 0 ] || [ -z "$SYNC_TYPE" ]; then
    exit 0
fi

case "$SYNC_TYPE" in
    "cloud_to_local"|"mirror_cloud")
        zenity --warning \
            --title="Внимание!" \
            --text="⚠️ Локальные файлы будут УДАЛЕНЫ если их нет в облаке!\n\nЭто действие необратимо!" \
            --width=400
        ;;
    "local_to_cloud"|"mirror_local")
        zenity --warning \
            --title="Внимание!" \
            --text="⚠️ Файлы в облаке будут УДАЛЕНЫ если их нет локально!\n\nЭто действие необратимо!" \
            --width=400
        ;;
esac

zenity --question \
    --title="Последнее подтверждение" \
    --text="Начать синхронизацию $SYNC_TYPE?\n\n$LOCAL_DIR\n⇄\n$CLOUD_PATH" \
    --ok-label="ЗАПУСТИТЬ СИНХРОНИЗАЦИЮ" \
    --cancel-label="ОТМЕНА" \
    --width=400 || exit 0

WORK_MOUNT="$HOME/cloud_work_${CLOUD_REMOTE}"
mkdir -p "$WORK_MOUNT"
rclone mount "$CLOUD_REMOTE:" "$WORK_MOUNT" --daemon --vfs-cache-mode writes
sleep 2

if [ -z "$RELATIVE_PATH" ]; then
    MOUNTED_CLOUD_PATH="$WORK_MOUNT"
else
    MOUNTED_CLOUD_PATH="$WORK_MOUNT/$RELATIVE_PATH"
fi

(
    echo "10"
    echo "# Инициализация синхронизации..."
    
    echo "20"
    echo "# Анализ файлов..."
    
    LOCAL_COUNT=$(find "$LOCAL_DIR" -type f 2>/dev/null | wc -l)
    CLOUD_COUNT=$(find "$MOUNTED_CLOUD_PATH" -type f 2>/dev/null | wc -l)
    
    echo "# Локальных файлов: $LOCAL_COUNT"
    echo "# Файлов в облаке: $CLOUD_COUNT"
    
    echo "30"
    echo "# Выполнение синхронизации типа: $SYNC_TYPE..."
    
    case "$SYNC_TYPE" in
        "cloud_to_local")
            rsync -avh --progress --stats --delete \
                --exclude=".*" \
                --exclude="*.tmp" \
                "$MOUNTED_CLOUD_PATH/" "$LOCAL_DIR/" 2>&1
            ;;
            
        "local_to_cloud")
            rsync -avh --progress --stats --delete \
                --exclude=".*" \
                --exclude="*.tmp" \
                "$LOCAL_DIR/" "$MOUNTED_CLOUD_PATH/" 2>&1
            ;;
            
        "two_way")
            echo "40"
            echo "# Этап 1: Облако → Локально (новые файлы)..."
            rsync -avhu --progress \
                "$MOUNTED_CLOUD_PATH/" "$LOCAL_DIR/" 2>&1 | tail -5
            
            echo "70"
            echo "# Этап 2: Локально → Облако (новые файлы)..."
            rsync -avhu --progress \
                "$LOCAL_DIR/" "$MOUNTED_CLOUD_PATH/" 2>&1 | tail -5
            ;;
            
        "copy_new_only")
            rsync -avhu --progress \
                "$MOUNTED_CLOUD_PATH/" "$LOCAL_DIR/" 2>&1 | tail -5
            
            rsync -avhu --progress \
                "$LOCAL_DIR/" "$MOUNTED_CLOUD_PATH/" 2>&1 | tail -5
            ;;
            
        "mirror_cloud")
            rsync -avh --progress --stats --delete --delete-excluded \
                --exclude=".*" \
                "$MOUNTED_CLOUD_PATH/" "$LOCAL_DIR/" 2>&1
            ;;
            
        "mirror_local")
            rsync -avh --progress --stats --delete --delete-excluded \
                --exclude=".*" \
                "$LOCAL_DIR/" "$MOUNTED_CLOUD_PATH/" 2>&1
            ;;
    esac
    
    SYNC_EXIT=$?
    
    echo "90"
    echo "# Завершение работы..."
    
    fusermount -u "$WORK_MOUNT" 2>/dev/null
    rmdir "$WORK_MOUNT" 2>/dev/null
    
    if [ $SYNC_EXIT -eq 0 ]; then
        echo "100"
        echo "# Синхронизация успешно завершена!"
    else
        echo "# Синхронизация завершена с ошибкой!"
    fi
    
) | zenity --progress \
    --title="Синхронизация: $SYNC_TYPE" \
    --text="Подготовка..." \
    --percentage=0 \
    --auto-close \
    --width=500 \
    --height=150

SYNC_RESULT=${PIPESTATUS[1]}

if [ $SYNC_RESULT -eq 0 ]; then
    # Считаем итоговое количество файлов
    FINAL_LOCAL=$(find "$LOCAL_DIR" -type f 2>/dev/null | wc -l)
    
    REPORT="✅ СИНХРОНИЗАЦИЯ ЗАВЕРШЕНА\n\n"
    REPORT+="Тип: $SYNC_TYPE\n"
    REPORT+="Облако: $CLOUD_REMOTE\n"
    REPORT+="Файлов локально: $FINAL_LOCAL\n\n"
    
    case "$SYNC_TYPE" in
        "cloud_to_local"|"mirror_cloud")
            REPORT+="Локальная папка теперь зеркало облака."
            ;;
        "local_to_cloud"|"mirror_local")
            REPORT+="Облако теперь зеркало локальной папки."
            ;;
        "two_way"|"copy_new_only")
            REPORT+="Папки объединены (двусторонняя синхронизация)."
            ;;
    esac
    
    zenity --info \
        --title="Отчет о синхронизации" \
        --text="$REPORT" \
        --width=500
    
    echo "=== Статистика синхронизации ==="
    echo "Тип: $SYNC_TYPE"
    echo "Облако: $CLOUD_PATH"
    echo "Локально: $LOCAL_DIR"
    echo "Локальных файлов: $FINAL_LOCAL"
    
else
    zenity --error \
        --title="Ошибка синхронизации" \
        --text="❌ Синхронизация не удалась!\n\nКод ошибки: $SYNC_RESULT\n\nПроверьте:\n• Подключение к интернету\n• Достаточно ли места\n• Права доступа к файлам" \
        --width=500
fi

# Очистка (на всякий случай)
pkill -f "rclone mount $CLOUD_REMOTE:" 2>/dev/null
rmdir "$HOME/cloud_"* 2>/dev/null
