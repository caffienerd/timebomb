#!/bin/sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PYTHON_DIR="$SCRIPT_DIR/python"
APP="$PYTHON_DIR/timebomb.py"
PYTHON="$PYTHON_DIR/venv/bin/python3"

if [ ! -x "$PYTHON" ]; then
    PYTHON="/usr/bin/python3"
fi

show_timebomb() {
    "$PYTHON" "$APP" --show >/dev/null 2>&1
}

if show_timebomb; then
    exit 0
fi

SERVICE_AVAILABLE=false
if command -v systemctl >/dev/null 2>&1; then
    if systemctl --user start timebomb.service >/dev/null 2>&1; then
        SERVICE_AVAILABLE=true
    fi
fi

i=0
while [ "$i" -lt 25 ]; do
    sleep 0.2
    if show_timebomb; then
        exit 0
    fi
    i=$((i + 1))
done

if [ "$SERVICE_AVAILABLE" = true ]; then
    exit 1
fi

env GDK_BACKEND=wayland,x11 "$PYTHON" "$APP" >/dev/null 2>&1 &

i=0
while [ "$i" -lt 25 ]; do
    sleep 0.2
    if show_timebomb; then
        exit 0
    fi
    i=$((i + 1))
done

exit 1
