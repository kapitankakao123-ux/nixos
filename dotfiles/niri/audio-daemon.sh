#!/usr/bin/env bash

HEADPHONES_NAME="CMF Headphone Pro"
HDMI_NAME="Navi 48 HDMI/DP Audio Controller"
VIRTUAL_NAME="sink-sunshine-stereo"

LAST_WS=""
LAST_PID=""

get_info() {
    niri msg focused-window 2>/dev/null
}

extract_pid() {
    grep "PID:" | awk '{print $2}'
}

extract_workspace() {
    grep "Workspace ID:" | awk '{print $3}'
}

get_sink_id_by_name() {
    wpctl status | grep -i "$1" | grep -Eo '^[[:space:]]*[0-9]+' | tr -d ' '
}

get_stream_ids_by_app() {
    local APP="$1"

    wpctl status | awk '/Streams:/,/Sinks:/' | grep -Eo '^[[:space:]]*[0-9]+\.' | tr -d '.' | while read -r ID; do
        wpctl inspect "$ID" 2>/dev/null | grep -qi "application.name.*$APP" && echo "$ID"
    done
}

is_headphones_available() {
    wpctl status | grep -q "$HEADPHONES_NAME"
}

while true; do
    INFO=$(get_info)

    PID=$(echo "$INFO" | extract_pid)
    WS=$(echo "$INFO" | extract_workspace)

    # 🔥 ТРИГГЕР: отдельно по workspace И pid
    if [ "$WS" != "$LAST_WS" ] || [ "$PID" != "$LAST_PID" ]; then

	APP_ID=$(echo "$INFO" | grep "App ID:" | awk -F '"' '{print $2}')
	STREAM_IDS=$(get_stream_ids_by_app "$APP_ID") 
	if [ -n "$STREAM_IDS" ]; then

            if [ "$WS" = "1" ]; then
                if is_headphones_available; then
                    TARGET=$(get_sink_id_by_name "$HEADPHONES_NAME")
                else
                    TARGET=$(get_sink_id_by_name "$HDMI_NAME")
                fi
            elif [ "$WS" = "14" ]; then
                TARGET=$(get_sink_id_by_name "$VIRTUAL_NAME")
            else
                TARGET=""
            fi

            if [ -n "$TARGET" ]; then
                for SID in $STREAM_IDS; do
                    wpctl move "$SID" "$TARGET"
                done
            fi
        fi

        LAST_WS="$WS"
        LAST_PID="$PID"
    fi

    sleep 0.2
done
