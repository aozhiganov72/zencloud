#!/bin/bash
MOUNT_BASE_DIR="$HOME/Clouds"
mkdir -p "$MOUNT_BASE_DIR"
rclone listremotes 2>/dev/null | while read Cloud; do
    Cloud="${Cloud//:/}"
    mkdir -p ~/Clouds/"$Cloud"
    rclone mount "$Cloud:" ~/Clouds/"$Cloud" --daemon \
        --vfs-cache-mode writes \
        --vfs-cache-max-age 10s \
        --dir-cache-time 5s \
        --poll-interval 30s
done
xdg-open $HOME/Clouds/
