#!/bin/bash

echo "======================================"
echo "   TimeBomb Uninstallation Script"
echo "======================================"
echo ""

if [ "$EUID" -eq 0 ]; then 
   echo "ERROR: Do not run this script as root!"
   echo "Run as your normal user instead."
   exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PYTHON_DIR="$SCRIPT_DIR/python"
VENV_DIR="$PYTHON_DIR/venv"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SYSTEMD_USER_DIR/timebomb.service"
XDG_AUTOSTART_FILE="$HOME/.config/autostart/timebomb.desktop"
FONT_DIR="$HOME/.local/share/fonts"

echo "This will remove:"
echo "  - TimeBomb systemd service (if exists)"
echo "  - TimeBomb XDG autostart entry (if exists)"
echo "  - Python virtual environment"
echo "  - DS Digital fonts"
echo "  - Log files"
echo ""
echo "This will NOT remove:"
echo "  - System packages (Python, GTK, etc.)"
echo "  - Your timer/stopwatch state"
echo "  - The TimeBomb source code"
echo ""
read -p "Continue with uninstallation? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

echo ""
echo "[1/6] Stopping and removing systemd service..."
if [ -f "$SERVICE_FILE" ]; then
    # Stop the service if running
    if systemctl --user is-active --quiet timebomb.service; then
        systemctl --user stop timebomb.service
        echo "✓ Service stopped"
    fi
    
    # Disable the service
    if systemctl --user is-enabled --quiet timebomb.service 2>/dev/null; then
        systemctl --user disable timebomb.service
        echo "✓ Service disabled"
    fi
    
    # Remove the service file
    rm -f "$SERVICE_FILE"
    echo "✓ Service file removed"
    
    # Reload systemd daemon
    systemctl --user daemon-reload
    echo "✓ Systemd daemon reloaded"
else
    echo "⊘ No systemd service found"
fi

echo ""
echo "[2/6] Removing XDG autostart entry (legacy)..."
if [ -f "$XDG_AUTOSTART_FILE" ]; then
    rm -f "$XDG_AUTOSTART_FILE"
    echo "✓ XDG autostart entry removed"
else
    echo "⊘ No XDG autostart entry found"
fi

echo ""
echo "[3/6] Removing Python virtual environment..."
if [ -d "$VENV_DIR" ]; then
    rm -rf "$VENV_DIR"
    echo "✓ Virtual environment removed"
else
    echo "⊘ No virtual environment found"
fi

echo ""
echo "[4/6] Removing DS Digital fonts..."
if ls "$FONT_DIR"/DS-DIGI*.TTF 1> /dev/null 2>&1; then
    rm -f "$FONT_DIR"/DS-DIGI*.TTF
    fc-cache -f "$FONT_DIR" 2>/dev/null
    echo "✓ DS Digital fonts removed"
else
    echo "⊘ No DS Digital fonts found"
fi

echo ""
echo "[5/6] Cleaning log files..."
if [ -d "$SCRIPT_DIR/assets/logs" ]; then
    rm -f "$SCRIPT_DIR/assets/logs"/*.log
    echo "✓ Log files removed"
else
    echo "⊘ No log directory found"
fi

echo ""
echo "[6/6] Removing user from 'input' group..."
read -p "Remove yourself from 'input' group? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if groups | grep -q '\binput\b'; then
        sudo gpasswd -d "$USER" input || {
            echo "ERROR: Failed to remove from input group"
            echo "Run manually: sudo gpasswd -d $USER input"
        }
        echo "✓ Removed from input group"
        echo "⚠️  You MUST log out and back in for this to take effect!"
    else
        echo "⊘ Not in input group"
    fi
else
    echo "⊘ Skipped removing from input group"
fi

echo ""
echo "======================================"
echo "   Uninstallation Complete!"
echo "======================================"
echo ""
echo "Remaining items (manual cleanup if desired):"
echo "  - Source code: $SCRIPT_DIR"
echo "  - State file: $SCRIPT_DIR/assets/state/state.ini"
echo ""
echo "To completely remove TimeBomb:"
echo "  cd $(dirname "$SCRIPT_DIR") && rm -rf $(basename "$SCRIPT_DIR")"
echo ""