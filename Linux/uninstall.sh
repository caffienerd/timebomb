#!/bin/bash

echo "======================================"
echo "   TimeBomb Uninstallation Script"
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
SYSTEMD_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SYSTEMD_DIR/timebomb.service"

echo "[1/4] Stopping TimeBomb..."
# Try to stop via systemd first
if systemctl --user is-active --quiet timebomb.service 2>/dev/null; then
    systemctl --user stop timebomb.service
    echo "✓ Stopped systemd service"
fi

# Kill any running instances
pkill -f "python3.*timebomb.py" 2>/dev/null && echo "✓ Killed running instances"

echo ""
echo "[2/4] Removing systemd service..."
if [ -f "$SERVICE_FILE" ]; then
    systemctl --user disable timebomb.service 2>/dev/null
    rm -f "$SERVICE_FILE"
    systemctl --user daemon-reload
    echo "✓ Systemd service removed"
else
    echo "⊗ No systemd service found"
fi

echo ""
echo "[3/4] Cleaning up state files..."
read -p "Remove saved state and config files? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$SCRIPT_DIR/assets/state"
    echo "✓ State files removed"
else
    echo "⊗ Keeping state files"
fi

echo ""
echo "[4/4] Input group removal..."
read -p "Remove user from 'input' group? (may affect other apps) (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo gpasswd -d "$USER" input
    echo "✓ Removed from input group"
    echo "⚠️  Log out and back in for this to take effect"
else
    echo "⊗ Keeping input group membership"
fi

echo ""
echo "======================================"
echo "   Uninstallation Complete!"
echo "======================================"
echo ""
echo "TimeBomb has been removed from your system."
echo "The installation folder is still here if you want to delete it manually."
echo ""
echo "Thanks for using TimeBomb!!"