#!/bin/bash

DIR=$(zenity --file-selection --directory --filename="$HOME/" --title="Выберите папку для отправки в облако")

if [ $? -ne 0 ] || [ -z "$DIR" ]; then
    zenity --info --text="Операция отменена"
    exit 1
fi

if [ ! -d "$DIR" ]; then
    zenity --error --text="Директория не существует или недоступна:\n$DIR"
    exit 1
fi

FOLDER_NAME=$(basename "$DIR")
FOLDER_SIZE=$(du -sb "$DIR" 2>/dev/null | cut -f1)
FOLDER_SIZE_HR=$(numfmt --to=iec $FOLDER_SIZE)
FILE_COUNT=$(find "$DIR" -type f | wc -l)

CLOUDS=$(rclone listremotes 2>/dev/null | sed 's/://g' | tr '\n' '|' | sed 's/|$//')
[ -z "$CLOUDS" ] && zenity --error --text="Нет облаков! rclone config" && exit 1

CLOUD=$(zenity --forms --title="Выбор облака"\
    --text="Выберите облако" \
    --combo-values=$CLOUDS\
    --add-combo="Ваш выбор")
[ $? -ne 0 ] && exit 0

zenity --question \
    --title="Подтверждение отправки" \
    --text="Выбрана папка: $FOLDER_NAME\nРазмер: $FOLDER_SIZE_HR\nФайлов: $FILE_COUNT\n\nОтправить в облако $CLOUD:$FOLDER_NAME ?" \
    --width=450 \
    --ok-label="Отправить" \
    --cancel-label="Отмена"

if [ $? -ne 0 ]; then
    zenity --info --text="Отправка отменена"
    exit 1
fi

LOG_FILE=$(mktemp)

(
    echo "0"
    echo "# Подготовка к отправке папки..."
    
    # Проверяем доступность облака
    echo "10"
    echo "# Проверка подключения к облаку..."
    
    # Создаем папку в облаке
    echo "20"
    echo "# Создание папки в облаке..."
    rclone mkdir "Home:$FOLDER_NAME" 2>/dev/null
    
    echo "30"
    echo "# Начинаем загрузку: $FOLDER_NAME"
    echo "# Файлов: $FILE_COUNT, Общий размер: $FOLDER_SIZE_HR"
    
    # Отправляем папку
    rclone copy "$DIR" "$CLOUD:$FOLDER_NAME" \
        -P \
        --transfers 4 \
        --checkers 8 \
        --stats-one-line \
        --progress \
        2>>"$LOG_FILE"
    
    RCLONE_EXIT_CODE=$?
    
    if [ $RCLONE_EXIT_CODE -eq 0 ]; then
        echo "100"
        echo "# Загрузка папки завершена успешно!"
    else
        echo "# Ошибка загрузки! Код: $RCLONE_EXIT_CODE"
    fi
) | zenity --progress \
    --title="Отправка папки в облако" \
    --text="Идет загрузка папки..." \
    --percentage=0 \
    --auto-close \
    --width=500 \
    --height=150

if [ ${PIPESTATUS[1]} -eq 0 ]; then
    # Проверяем, что папка появилась в облаке
    echo "# Проверка результата..."
    CLOUD_CONTENT=$(rclone lsd "$CLOUD:$FOLDER_NAME" 2>/dev/null)
    CLOUD_FILES=$(rclone ls "$CLOUD:$FOLDER_NAME" | wc -l)
    
    if [ -n "$CLOUD_CONTENT" ] || [ $CLOUD_FILES -gt 0 ]; then
        zenity --info \
            --text="✅ Папка успешно отправлена в облако!\n\n📁 Папка: $FOLDER_NAME\n💾 Размер: $FOLDER_SIZE_HR\n📊 Файлов: $FILE_COUNT\n📍 Путь: $CLOUD:$FOLDER_NAME\n☁️ Загружено файлов: $CLOUD_FILES" \
            --width=500
    else
        ERROR_LOG=$(tail -n 10 "$LOG_FILE")
        zenity --warning \
            --text="⚠️ Папка не найдена в облаке после загрузки.\n\nЛог ошибки:\n${ERROR_LOG}" \
            --width=600
    fi
else
    ERROR_LOG=$(tail -n 10 "$LOG_FILE")
    zenity --error \
        --text="❌ Ошибка при отправке папки!\n\nЛог ошибки:\n${ERROR_LOG}" \
        --width=600
fi

rm -f "$LOG_FILE"
