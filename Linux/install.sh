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

# Get the script directory (this is the Linux/ folder)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PYTHON_DIR="$SCRIPT_DIR/python"
VENV_DIR="$PYTHON_DIR/venv"

# Detect package manager and distro
detect_package_manager() {
    if command -v apt &> /dev/null; then
        PKG_MANAGER="apt"
        PKG_INSTALL="sudo apt install -y"
        PACKAGES="python3 python3-venv python3-pip gtk-layer-shell libgtk-3-0 python3-gi gir1.2-gtk-3.0 pulseaudio-utils fontconfig"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="sudo dnf install -y"
        PACKAGES="python3 gtk-layer-shell gtk3 python3-gobject pulseaudio-utils fontconfig"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        PKG_INSTALL="sudo pacman -S --needed --noconfirm"
        PACKAGES="python gtk-layer-shell gtk3 python-gobject pulseaudio fontconfig"
    elif command -v zypper &> /dev/null; then
        PKG_MANAGER="zypper"
        PKG_INSTALL="sudo zypper install -y"
        PACKAGES="python3 gtk-layer-shell gtk3 python3-gobject pulseaudio-utils fontconfig"
    else
        echo "ERROR: Could not detect package manager!"
        echo "Supported: apt (Debian/Ubuntu), dnf (Fedora/RHEL), pacman (Arch), zypper (openSUSE)"
        echo ""
        echo "Please install these packages manually:"
        echo "  - Python 3"
        echo "  - python3-venv"
        echo "  - GTK 3"
        echo "  - GTK Layer Shell"
        echo "  - Python GObject bindings"
        echo "  - PulseAudio utilities"
        echo "  - fontconfig"
        exit 1
    fi
    
    echo "✓ Detected package manager: $PKG_MANAGER"
}

echo "[1/8] Detecting system..."
detect_package_manager

echo ""
echo "[2/8] Checking Python installation..."
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is not installed!"
    echo "Install it with: $PKG_INSTALL python3"
    exit 1
fi
echo "✓ Python 3 found: $(python3 --version)"

echo ""
echo "[3/8] Installing system dependencies..."
read -p "Install system packages? This requires sudo. (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    $PKG_INSTALL $PACKAGES || {
        echo "WARNING: Some packages failed to install."
        echo "TimeBomb may not work properly without all dependencies."
    }
    echo "✓ System packages installed"
else
    echo "⊘ Skipped system package installation"
    echo "WARNING: Make sure you have all required dependencies installed!"
fi

echo ""
echo "[4/8] Installing DS Digital font (required for timer display)..."
FONT_DIR="$HOME/.local/share/font"
FONT_SOURCE="$SCRIPT_DIR/assets/font/DS-DIGI.TTF"
FONT_DEST="$FONT_DIR/DS-DIGI.TTF"

# Check if font source exists in repo
if [ ! -f "$FONT_SOURCE" ]; then
    echo "ERROR: Font file not found at $FONT_SOURCE"
    echo "Please ensure the repository is complete."
    exit 1
fi

mkdir -p "$FONT_DIR"

# Check if font already installed
if [ -f "$FONT_DEST" ]; then
    echo "✓ DS Digital font already installed"
else
    echo "Copying DS Digital font..."
    cp "$FONT_SOURCE" "$FONT_DEST" || {
        echo "ERROR: Failed to copy font"
        exit 1
    }
    
    # Refresh font cache
    fc-cache -f "$FONT_DIR" 2>/dev/null
    echo "✓ DS Digital font installed"
fi

echo ""
echo "[5/8] Creating Python virtual environment..."
if [ -d "$VENV_DIR" ]; then
    echo "Virtual environment already exists. Recreating..."
    rm -rf "$VENV_DIR"
fi

python3 -m venv "$VENV_DIR" || {
    echo "ERROR: Failed to create virtual environment!"
    echo "Make sure python3-venv is installed:"
    echo "  $PKG_INSTALL python3-venv"
    exit 1
}
echo "✓ Virtual environment created at: $VENV_DIR"

echo ""
echo "[6/8] Installing Python packages in venv..."
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install evdev PyGObject || {
    echo "ERROR: Failed to install Python packages!"
    echo "This usually means system dependencies are missing."
    exit 1
}
echo "✓ Python packages installed"

echo ""
echo "[7/8] Adding user to 'input' group..."
if ! groups | grep -q '\binput\b'; then
    sudo usermod -a -G input "$USER" || {
        echo "ERROR: Failed to add user to input group!"
        echo "Run manually: sudo usermod -a -G input $USER"
        exit 1
    }
    echo "✓ Added to input group"
    echo "⚠️  You MUST log out and back in for this to take effect!"
    NEED_LOGOUT=true
else
    echo "✓ Already in input group"
    NEED_LOGOUT=false
fi

echo ""
echo "[8/8] Creating directories..."
mkdir -p "$SCRIPT_DIR/assets/state"
echo "✓ Directories created"

echo ""
echo "======================================"
echo "   Systemd Autostart Setup"
echo "======================================"
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
ExecStart=$VENV_DIR/bin/python3 $PYTHON_DIR/timebomb.py
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
EOF
    
    systemctl --user daemon-reload
    systemctl --user enable timebomb.service
    
    echo "✓ Systemd service created and enabled (using X11 backend for stability)"
    echo ""
    echo "Service commands:"
    echo "  Start:   systemctl --user start timebomb.service"
    echo "  Stop:    systemctl --user stop timebomb.service"
    echo "  Status:  systemctl --user status timebomb.service"
    echo "  Restart: systemctl --user restart timebomb.service"
    echo "  Disable: systemctl --user disable timebomb.service"
    echo ""
    echo "To view logs: journalctl --user -u timebomb.service -f"
else
    echo "⊘ Skipping autostart setup"
    echo ""
    echo "You can run TimeBomb manually with:"
    echo "  cd $PYTHON_DIR && env GDK_BACKEND=x11 $VENV_DIR/bin/python3 timebomb.py"
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
echo "  cd $PYTHON_DIR && env GDK_BACKEND=x11 $VENV_DIR/bin/python3 timebomb.py"
echo ""
echo "Default keybinds (all use Win key):"
echo "  Win + \`         - Toggle visibility"
echo "  Win + Enter     - Pause/Resume"
echo "  Win + Backspace - Reset"
echo "  Win + Esc       - Switch Timer/Stopwatch"
echo "  Win + Up/Down   - Adjust timer (Timer mode only)"
echo ""
echo "Enjoy!! 🚀"