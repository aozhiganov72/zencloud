#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLOUDS=$(rclone listremotes 2>/dev/null | sed 's/://g' | tr '\n' '|' | sed 's/|$//')
[ -z "$CLOUDS" ] && zenity --error --text="Нет облаков! rclone config" && exit 1

ACTIONS=$(sqlite3 ${SCRIPT_DIR}/cloud.db "SELECT name FROM cloud" | tr '\n' '|')
IFS="|" StrAcs="${ACTIONS[*]::-1}"

SELECTED=$(zenity --forms --title="Выбор облака"\
    --text="Выберите действие" \
    --combo-values="$StrAcs"\
    --add-combo="Действие")
[ $? -ne 0 ] && exit 0
echo $SELECTED

if [ $? -ne 0 ] || [ -z "$SELECTED" ]; then
    exit 0
fi

# Запускаем выбранный скрипт
SCRIPT_NAME=$(sqlite3 ${SCRIPT_DIR}/cloud.db "SELECT script FROM cloud WHERE name='$SELECTED'")
SCRIPT_NAME=$SCRIPT_DIR/$SCRIPT_NAME
$SCRIPT_NAME

