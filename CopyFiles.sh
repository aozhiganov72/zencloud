#!/bin/bash

SELECTED_FILES=$(zenity --file-selection --multiple --separator=" " --filename="$HOME/")
[ $? -ne 0 ] && exit 1

IFS=' ' read -ra FILES <<< "$SELECTED_FILES"

CLOUDS=$(rclone listremotes 2>/dev/null | sed 's/://g' | tr '\n' '|' | sed 's/|$//')
[ -z "$CLOUDS" ] && zenity --error --text="Нет облаков! rclone config" && exit 1

CLOUD=$(zenity --forms --title="Выбор облака"\
    --text="Выберите облако" \
    --combo-values=$CLOUDS\
    --add-combo="Ваш выбор")
[ $? -ne 0 ] && exit 0

(
    echo "0"
    TOTAL=${#FILES[@]}
    COUNTER=0
    
    for file in "${FILES[@]}"; do
        COUNTER=$((COUNTER + 1))
        PERCENT=$((COUNTER * 100 / TOTAL))
        
        echo "$PERCENT"
        echo "# Загрузка $(basename "$file") ($COUNTER/$TOTAL)"
        
        # Копируем каждый файл отдельно
        rclone copy "$file" "$CLOUD": -q
        
        if [ $? -eq 0 ]; then
            echo "# Успешно: $(basename "$file")"
        else
            echo "# Ошибка: $(basename "$file")"
        fi
    done
    
    echo "100"
    echo "# Все файлы обработаны"
) | zenity --progress --auto-close --width=500

UPLOADED=$(rclone lsf "$CLOUD" | wc -l)
zenity --info --text="Загружено файлов: $UPLOADED\nПроверьте: rclone ls '$CLOUD'"
