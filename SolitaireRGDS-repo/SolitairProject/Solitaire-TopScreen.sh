#!/bin/bash
# ========================================================
# Solitaire Launcher (Top Screen Target) for PortMaster
# ========================================================
SCRIPT_DIR="$(dirname "$0")"

if [ -f "$SCRIPT_DIR/Solitaire.sh" ]; then
    exec "$SCRIPT_DIR/Solitaire.sh" "top"
elif [ -f "$SCRIPT_DIR/SolitairProject/Solitaire.sh" ]; then
    exec "$SCRIPT_DIR/SolitairProject/Solitaire.sh" "top"
else
    echo "ERROR: Solitaire.sh not found!"
    exit 1
fi

