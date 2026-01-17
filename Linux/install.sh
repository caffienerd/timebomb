#!/bin/bash

echo "======================================"
echo "   TimeBomb Installation Script"
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

echo "[1/6] Checking Python installation..."
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is not installed!"
    echo "Install it with: sudo dnf install python3"
    exit 1
fi
echo "✓ Python 3 found"

echo ""
echo "[2/6] Installing Python dependencies..."
pip3 install --user evdev PyGObject || {
    echo "WARNING: pip install failed, trying system packages..."
    echo "Run: sudo dnf install python3-evdev python3-gobject gtk3"
    read -p "Press Enter after installing system packages..."
}

echo ""
echo "[3/6] Checking GTK and GtkLayerShell..."
if ! python3 -c "import gi; gi.require_version('Gtk', '3.0')" 2>/dev/null; then
    echo "ERROR: GTK 3 not found!"
    echo "Install with: sudo dnf install gtk3 python3-gobject"
    exit 1
fi
echo "✓ GTK 3 found"

if ! python3 -c "import gi; gi.require_version('GtkLayerShell', '0.1')" 2>/dev/null; then
    echo "WARNING: GtkLayerShell not found (needed for Wayland overlay)"
    echo "Install with: sudo dnf install gtk-layer-shell"
    echo "TimeBomb will still work but might not stay above fullscreen apps on Wayland"
else
    echo "✓ GtkLayerShell found"
fi

echo ""
echo "[4/6] Adding user to 'input' group..."
if ! groups | grep -q '\binput\b'; then
    sudo usermod -a -G input "$USER"
    echo "✓ Added to input group"
    echo "⚠️  You MUST log out and back in for this to take effect!"
    NEED_LOGOUT=true
else
    echo "✓ Already in input group"
    NEED_LOGOUT=false
fi

echo ""
echo "[5/6] Creating directories..."
mkdir -p "$SCRIPT_DIR/assets/state"
echo "✓ Directories created"

echo ""
echo "[6/6] Systemd autostart setup"
read -p "Do you want TimeBomb to start automatically on login? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    SERVICE_FILE="$SYSTEMD_DIR/timebomb.service"
    
    mkdir -p "$SYSTEMD_DIR"
    
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=TimeBomb - Floating Timer/Stopwatch
After=graphical-session.target

[Service]
Environment=GDK_BACKEND=x11
Environment=DISPLAY=:0
WorkingDirectory=$PYTHON_DIR
ExecStart=/usr/bin/python3 $PYTHON_DIR/timebomb.py
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
EOF
    
    systemctl --user daemon-reload
    systemctl --user enable timebomb.service
    
    echo "✓ Systemd service created and enabled"
    echo ""
    echo "Service commands:"
    echo "  Start:   systemctl --user start timebomb.service"
    echo "  Stop:    systemctl --user stop timebomb.service"
    echo "  Status:  systemctl --user status timebomb.service"
    echo "  Disable: systemctl --user disable timebomb.service"
else
    echo "⊗ Skipping autostart setup"
    echo "You can run TimeBomb manually with:"
    echo "  cd $PYTHON_DIR && python3 timebomb.py"
fi

echo ""
echo "======================================"
echo "   Installation Complete!"
echo "======================================"
echo ""

if [ "$NEED_LOGOUT" = true ]; then
    echo "⚠️  IMPORTANT: Log out and back in for 'input' group to take effect!"
    echo ""
fi

echo "To start TimeBomb now (if not using autostart):"
echo "  cd $PYTHON_DIR && python3 timebomb.py"
echo ""
echo "Default keybinds (all use Win key):"
echo "  Win + \`         - Toggle visibility"
echo "  Win + Enter     - Pause/Resume"
echo "  Win + Backspace - Reset"
echo "  Win + Esc       - Switch Timer/Stopwatch"
echo "  Win + Up/Down   - Adjust timer (Timer mode only)"
echo ""
echo "Enjoy!!"