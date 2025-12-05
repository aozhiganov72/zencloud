#!/bin/bash

FILE=$(zenity --file-selection --filename="$HOME/" --title="Выберите файл для отправки в облако")

if [ $? -ne 0 ] || [ -z "$FILE" ]; then
    zenity --info --text="Операция отменена"
    exit 1
fi

if [ ! -f "$FILE" ]; then
    zenity --error --text="Файл не существует или недоступен:\n$FILE"
    exit 1
fi

FILENAME=$(basename "$FILE")
FILESIZE=$(stat -c%s "$FILE" 2>/dev/null || stat -f%z "$FILE")
FILESIZE_HR=$(numfmt --to=iec $FILESIZE)

CLOUDS=$(rclone listremotes 2>/dev/null | sed 's/://g' | tr '\n' '|' | sed 's/|$//')
[ -z "$CLOUDS" ] && zenity --error --text="Нет облаков! rclone config" && exit 1

CLOUD=$(zenity --forms --title="Выбор облака"\
    --text="Выберите облако" \
    --combo-values=$CLOUDS\
    --add-combo="Ваш выбор")
[ $? -ne 0 ] && exit 0

zenity --question \
    --title="Подтверждение отправки" \
    --text="Выбран файл: $FILENAME\nРазмер: $FILESIZE_HR\n\nОтправить в облако $CLOUD:/ ?" \
    --width=400 \
    --ok-label="Отправить" \
    --cancel-label="Отмена"

if [ $? -ne 0 ]; then
    zenity --info --text="Отправка отменена"
    exit 1
fi

(
    echo "0"
    echo "# Подготовка к отправке: $FILENAME"
    
    rclone mkdir $CLOUD:/ 2>/dev/null
    
    echo "10"
    echo "# Начинаем загрузку файла ($FILESIZE_HR)..."
    
    rclone copy "$FILE" $CLOUD: \
        -P \
        --transfers 1 \
        --checkers 2 \
        --progress \
        --stats-one-line
    
    RCLONE_EXIT_CODE=$?
    
    if [ $RCLONE_EXIT_CODE -eq 0 ]; then
        echo "100"
        echo "# Файл успешно загружен!"
    else
        echo "# Ошибка при загрузке! Код: $RCLONE_EXIT_CODE"
    fi
) | zenity --progress \
    --title="Отправка в облако" \
    --text="Идет загрузка файла..." \
    --percentage=0 \
    --auto-close \
    --width=500

if [ ${PIPESTATUS[1]} -eq 0 ]; then
    CHECK_FILE=$(rclone lsf $CLOUD:/"$FILENAME" 2>/dev/null)
    
    if [ "$CHECK_FILE" = "$FILENAME" ]; then
        zenity --info \
            --text="Файл успешно отправлен в облако!\n\n• Файл: $FILENAME\n• Размер: $FILESIZE_HR\n• Путь: $CLOUD:/" \
            --width=450
    else
        zenity --warning \
            --text="Возникла проблема!\n\nФайл '$FILENAME' не найден в облаке после загрузки.\n\nПроверьте настройки rclone." \
            --width=500
    fi
else
    zenity --error \
        --text="Ошибка при отправке файла!\n\nПроверьте:\n• Подключение к интернету\n• Настройки облака $CLOUD:\n• Права доступа" \
        --width=500
fi
