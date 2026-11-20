#!/bin/bash
# ========================================================
# Solitaire Launcher for Anbernic RG DS Plus (BananaOS)
# ========================================================

# 1. Determine PortMaster control folder
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

# 2. Source PortMaster core controls
if [ -f "${controlfolder}/control.txt" ]; then
  source "${controlfolder}/control.txt"
  [ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
  get_controls
fi

# 3. Resolve Game Directory
SCRIPT_DIR="$(dirname "$0")"
if [ -f "$SCRIPT_DIR/SolitairProject/main.lua" ]; then
    GAMEDIR="$SCRIPT_DIR/SolitairProject"
elif [ -f "$SCRIPT_DIR/solitaire/main.lua" ]; then
    GAMEDIR="$SCRIPT_DIR/solitaire"
elif [ -f "$SCRIPT_DIR/main.lua" ]; then
    GAMEDIR="$SCRIPT_DIR"
else
    GAMEDIR="$SCRIPT_DIR/SolitairProject"
fi

cd "$GAMEDIR"

# 4. Universal POSIX logging
exec > "$GAMEDIR/log.txt" 2>&1
echo "=== Solitaire Launch Log ==="
echo "Date: $(date)"
echo "GAMEDIR: $GAMEDIR"
echo "controlfolder: $controlfolder"
echo "CFW_NAME: $CFW_NAME"

# Probe DRM connectors on system
echo "=== DRM Hardware Connectors ==="
for d in /sys/class/drm/card*-*; do
    if [ -f "$d/status" ]; then
        echo "  $(basename "$d"): status=$(cat "$d/status" 2>/dev/null) enabled=$(cat "$d/enabled" 2>/dev/null)"
    fi
done

# Wake and maximize ALL display backlights (prevents bottom or top screen from shutting off)
echo "=== Backlight Management ==="
for bl in /sys/class/backlight/*; do
    if [ -d "$bl" ]; then
        cur_b=$(cat "$bl/brightness" 2>/dev/null)
        max_b=$(cat "$bl/max_brightness" 2>/dev/null)
        echo "  $(basename "$bl"): current=$cur_b, max=$max_b"
        if [ -n "$max_b" ] && [ "$max_b" -gt 0 ] 2>/dev/null; then
            echo "$max_b" > "$bl/brightness" 2>/dev/null
            echo "  $(basename "$bl"): set to max ($max_b)"
        fi
        # bl_power: 0 = on, 4 = powered down. Brightness alone cannot wake a powered-down backlight.
        if [ -f "$bl/bl_power" ]; then
            echo "  $(basename "$bl"): bl_power was $(cat "$bl/bl_power" 2>/dev/null)"
            echo 0 > "$bl/bl_power" 2>/dev/null
            echo "  $(basename "$bl"): bl_power now $(cat "$bl/bl_power" 2>/dev/null)"
        fi
    fi
done

# Wake DPMS displays
for d in /sys/class/drm/card*-*; do
    if [ -f "$d/dpms" ]; then
        echo "On" > "$d/dpms" 2>/dev/null
    fi
done

# 5. Screen Selection (Bottom Touchscreen vs Top Screen)
# "bottom" = Connector 1 (Bottom Touchscreen) [DEFAULT]
# "top"    = Connector 0 (Top Screen)
TARGET_SCREEN="bottom"
if [ "$1" = "top" ] || [ "$1" = "bottom" ]; then
    TARGET_SCREEN="$1"
elif [ -f "$GAMEDIR/screen.txt" ]; then
    TARGET_SCREEN=$(cat "$GAMEDIR/screen.txt" | tr -d ' \r\n')
fi

echo "Selected TARGET_SCREEN: $TARGET_SCREEN"

if [ "$TARGET_SCREEN" = "top" ]; then
    echo "Routing video to: TOP SCREEN (single-screen mode, L2 toggles wallpaper)"
    export SDL_KMSDRM_CONNECTOR_INDEX=0
    export LOVE_TARGET_DISPLAY=1
    export DUAL_SCREEN=0
else
    echo "Routing video to: BOTTOM TOUCHSCREEN (game) + TOP SCREEN (wallpaper & stats)"
    export SDL_KMSDRM_CONNECTOR_INDEX=1
    export LOVE_TARGET_DISPLAY=2
    export DUAL_SCREEN=1
fi

# Optional: If fbv or fbi is installed and we are running on bottom screen, show top_bg on fb0
if [ "$TARGET_SCREEN" = "bottom" ] && [ "$DUAL_SCREEN" != "1" ] && [ -f "$GAMEDIR/assets/backgrounds/top_bg.jpg" ]; then
    if command -v fbv >/dev/null 2>&1; then
        echo "Displaying top_bg on framebuffer with fbv..."
        fbv -d 0 "$GAMEDIR/assets/backgrounds/top_bg.jpg" &
    elif command -v fbi >/dev/null 2>&1; then
        echo "Displaying top_bg on framebuffer with fbi..."
        fbi -d /dev/fb0 -noverbose -a "$GAMEDIR/assets/backgrounds/top_bg.jpg" &
    fi
fi

# 6. Locate LÖVE2D Runtime
LOVE_FOUND=0

for rver in "love_11.5" "love_11.4" "love" "love_11.3"; do
    if [ -f "$controlfolder/runtimes/$rver/love.txt" ]; then
        echo "Found PortMaster runtime: $rver"
        source "$controlfolder/runtimes/$rver/love.txt"
        LOVE_FOUND=1
        break
    fi
done

# Prepend runtime library directory to LD_LIBRARY_PATH
if [ -n "$LOVE_BINARY" ]; then
    RUNTIME_DIR="$(dirname "$LOVE_BINARY")"
    if [ -d "$RUNTIME_DIR/libs.aarch64" ]; then
        export LD_LIBRARY_PATH="$RUNTIME_DIR/libs.aarch64:$LD_LIBRARY_PATH"
    fi
    [ -f "$LOVE_BINARY" ] && chmod +x "$LOVE_BINARY"
fi

echo "LOVE_BINARY: $LOVE_BINARY"
echo "LOVE_RUN: $LOVE_RUN"
echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"

export SDL_VIDEO_X11_XRANDR=1
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# Start keymapper if configured
[ -n "$GPTOKEYB" ] && [ -n "$LOVE_GPTK" ] && [ -f "$LOVE_GPTK" ] && $GPTOKEYB "$LOVE_GPTK" &

# Choose target payload (prefer self-contained Solitaire.love if present)
if [ -f "$GAMEDIR/Solitaire.love" ]; then
    GAME_TARGET="$GAMEDIR/Solitaire.love"
else
    GAME_TARGET="$GAMEDIR"
fi

# 7. Execute Game
if [ $LOVE_FOUND -eq 1 ] && [ -n "$LOVE_RUN" ]; then
    echo "Applying pm_platform_helper..."
    pm_platform_helper "$LOVE_BINARY"
    
    echo "Executing via LOVE_RUN: $LOVE_RUN $GAME_TARGET"
    eval $LOVE_RUN "\"$GAME_TARGET\""
    EXIT_CODE=$?
    echo "Love exited with code: $EXIT_CODE"
elif [ $LOVE_FOUND -eq 1 ] && [ -n "$LOVE_BINARY" ]; then
    echo "Applying pm_platform_helper..."
    pm_platform_helper "$LOVE_BINARY"
    
    echo "Executing via LOVE_BINARY: $LOVE_BINARY $GAME_TARGET"
    "$LOVE_BINARY" "$GAME_TARGET"
    EXIT_CODE=$?
    echo "Love exited with code: $EXIT_CODE"
elif command -v love >/dev/null 2>&1; then
    echo "Launching with system love command"
    love "$GAME_TARGET"
elif [ -f "/usr/bin/love" ]; then
    echo "Launching with /usr/bin/love"
    /usr/bin/love "$GAME_TARGET"
elif [ -f "$controlfolder/libs/love" ]; then
    echo "Launching with $controlfolder/libs/love"
    "$controlfolder/libs/love" "$GAME_TARGET"
else
    echo "ERROR: Love2D runtime not found!"
fi

# Cleanup
if type pm_finish >/dev/null 2>&1; then
    pm_finish
fi
echo "=== End of Script ==="
