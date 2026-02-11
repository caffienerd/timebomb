#!/bin/bash

echo "======================================"
echo "   TimeBomb Uninstall Script"
echo "======================================"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
   echo "ERROR: Do not run this script as root!"
   echo "Run as your normal user instead."
   exit 1
fi

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PYTHON_DIR="$SCRIPT_DIR/python"
VENV_DIR="$PYTHON_DIR/venv"

echo "This will:"
echo "  - Remove the autostart entry"
echo "  - Remove the virtual environment"
echo "  - Optionally remove the DS Digital fonts"
echo "  - Optionally remove you from the 'input' group"
echo "  - Optionally remove state and log files"
echo ""
read -p "Continue with uninstall? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo ""
echo "[1/6] Stopping TimeBomb if running..."
pkill -f "timebomb.py" 2>/dev/null && echo "✓ TimeBomb stopped" || echo "⊘ TimeBomb not running"

echo ""
echo "[2/6] Removing autostart entry..."
AUTOSTART_FILE="$HOME/.config/autostart/timebomb.desktop"
if [ -f "$AUTOSTART_FILE" ]; then
    rm -f "$AUTOSTART_FILE"
    echo "✓ Autostart entry removed"
else
    echo "⊘ No autostart entry found"
fi

echo ""
echo "[3/6] Removing virtual environment..."
if [ -d "$VENV_DIR" ]; then
    rm -rf "$VENV_DIR"
    echo "✓ Virtual environment removed"
else
    echo "⊘ No virtual environment found"
fi

echo ""
echo "[4/6] Removing DS Digital fonts..."
read -p "Remove DS Digital fonts? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    FONT_DIR="$HOME/.local/share/fonts"
    FONTS_REMOVED=0
    
    for font in "$FONT_DIR"/DS-DIGI*.TTF; do
        if [ -f "$font" ]; then
            rm -f "$font"
            FONTS_REMOVED=$((FONTS_REMOVED + 1))
        fi
    done
    
    if [ $FONTS_REMOVED -gt 0 ]; then
        fc-cache -f "$FONT_DIR" 2>/dev/null
        echo "✓ Removed $FONTS_REMOVED DS Digital font variant(s)"
    else
        echo "⊘ No DS Digital fonts found"
    fi
else
    echo "⊘ Keeping DS Digital fonts"
fi

echo ""
echo "[5/6] Removing from 'input' group..."
if groups | grep -q '\binput\b'; then
    read -p "Remove yourself from 'input' group? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo gpasswd -d "$USER" input || {
            echo "ERROR: Failed to remove from input group"
            echo "Run manually: sudo gpasswd -d $USER input"
        }
        echo "✓ Removed from input group"
        echo "⚠️  You need to log out and back in for this to take effect!"
        NEED_LOGOUT=true
    else
        echo "⊘ Still in input group"
        NEED_LOGOUT=false
    fi
else
    echo "⊘ Not in input group"
    NEED_LOGOUT=false
fi

echo ""
echo "[6/6] Cleaning up data files..."
read -p "Remove saved state and logs? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    STATE_FILE="$SCRIPT_DIR/assets/state/state.ini"
    LOG_DIR="$SCRIPT_DIR/assets/logs"
    
    if [ -f "$STATE_FILE" ]; then
        rm -f "$STATE_FILE"
        echo "✓ State file removed"
    else
        echo "⊘ No state file found"
    fi
    
    if [ -d "$LOG_DIR" ]; then
        rm -f "$LOG_DIR"/*.log 2>/dev/null
        LOG_COUNT=$(ls -1 "$LOG_DIR"/*.log 2>/dev/null | wc -l)
        if [ $LOG_COUNT -eq 0 ]; then
            echo "✓ Log files removed"
        else
            echo "⊘ No log files found"
        fi
    fi
else
    echo "⊘ Keeping state and log files"
fi

echo ""
echo "======================================"
echo "   Uninstall Complete!"
echo "======================================"
echo ""

if [ "$NEED_LOGOUT" = true ]; then
    echo "⚠️  IMPORTANT: Log out and back in for group changes to take effect!"
    echo ""
fi

echo "Note: This script does NOT remove:"
echo "  - System packages (Python, GTK, etc.)"
echo "  - The TimeBomb source code folder"
echo ""
echo "To completely remove TimeBomb, delete this folder:"
echo "  rm -rf $SCRIPT_DIR"
echo ""
echo "Thanks for trying TimeBomb!"