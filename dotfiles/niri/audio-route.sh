#!/usr/bin/env bash

# ===== НАСТРОЙКИ =====
HEADPHONES_NAME="CMF Headphone Pro"
HDMI_NAME="Navi 48 HDMI/DP Audio Controller"
VIRTUAL_NAME="sink-sunshine-stereo"

# ===== ФУНКЦИИ =====

get_focused_pid() {
    niri msg --json focused-window | jq -r '.pid'
}

get_focused_output() {
    niri msg --json focused-window | jq -r '.output'
}

get_sink_id_by_name() {
    wpctl status | grep -i "$1" | grep -Eo '^[[:space:]]*[0-9]+' | tr -d ' '
}

get_stream_id_by_pid() {
    local PID="$1"
    wpctl status | awk -v pid="$PID" '
        $0 ~ "Streams:" {flag=1; next}
        $0 ~ "Sinks:" {flag=0}
        flag && $0 ~ pid {
            match($0, /^[[:space:]]*([0-9]+)\./, arr)
            if (arr[1] != "") print arr[1]
        }
    '
}

is_headphones_available() {
    wpctl status | grep -q "$HEADPHONES_NAME"
}

# ===== ЛОГИКА =====

PID=$(get_focused_pid)
OUTPUT=$(get_focused_output)

[ -z "$PID" ] && exit 0

STREAM_ID=$(get_stream_id_by_pid "$PID")

[ -z "$STREAM_ID" ] && exit 0

if [ "$OUTPUT" = "DP-1" ]; then
    if is_headphones_available; then
        TARGET=$(get_sink_id_by_name "$HEADPHONES_NAME")
    else
        TARGET=$(get_sink_id_by_name "$HDMI_NAME")
    fi
elif [ "$OUTPUT" = "Virtual-1" ]; then
    TARGET=$(get_sink_id_by_name "$VIRTUAL_NAME")
else
    exit 0
fi

[ -z "$TARGET" ] && exit 0

wpctl move "$STREAM_ID" "$TARGET"
