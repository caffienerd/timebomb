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
echo "  - Stop and disable the systemd service"
echo "  - Remove the virtual environment"
echo "  - Optionally remove the DS Digital font"
echo "  - Optionally remove you from the 'input' group"
echo ""
read -p "Continue with uninstall? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo ""
echo "[1/5] Stopping and disabling systemd service..."
SYSTEMD_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SYSTEMD_DIR/timebomb.service"

if [ -f "$SERVICE_FILE" ]; then
    systemctl --user stop timebomb.service 2>/dev/null
    systemctl --user disable timebomb.service 2>/dev/null
    rm -f "$SERVICE_FILE"
    systemctl --user daemon-reload
    echo "✓ Systemd service removed"
else
    echo "⊘ No systemd service found"
fi

echo ""
echo "[2/5] Removing virtual environment..."
if [ -d "$VENV_DIR" ]; then
    rm -rf "$VENV_DIR"
    echo "✓ Virtual environment removed"
else
    echo "⊘ No virtual environment found"
fi

echo ""
echo "[3/5] Removing DS Digital font..."
read -p "Remove DS Digital font? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    FONT_FILE="$HOME/.local/share/fonts/DS-DIGI.TTF"
    if [ -f "$FONT_FILE" ]; then
        rm -f "$FONT_FILE"
        fc-cache -f "$HOME/.local/share/fonts" 2>/dev/null
        echo "✓ DS Digital font removed"
    else
        echo "⊘ Font not found"
    fi
else
    echo "⊘ Keeping DS Digital font"
fi

echo ""
echo "[4/5] Removing from 'input' group..."
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
echo "[5/5] Cleaning up state files..."
read -p "Remove saved state (position, mode)? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    STATE_FILE="$SCRIPT_DIR/assets/state/state.ini"
    if [ -f "$STATE_FILE" ]; then
        rm -f "$STATE_FILE"
        echo "✓ State file removed"
    else
        echo "⊘ No state file found"
    fi
else
    echo "⊘ Keeping state file"
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