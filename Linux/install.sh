#!/bin/bash

echo "======================================"
echo "   TimeBomb Installation Script"
echo "======================================"
echo ""

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

if [ "$CURRENT_BRANCH" = "testing" ]; then
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                ⚠️  WARNING WARNING WARNING ⚠️              ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  YOU ARE INSTALLING FROM THE 'testing' BRANCH!"
    echo ""
    echo "  This branch contains:"
    echo "    - UNSTABLE code that may be broken"
    echo "    - EXPERIMENTAL features that may crash"
    echo "    - BUGS that could cause system issues"
    echo ""
    echo "  For stable code, switch to 'main' branch:"
    echo "    git checkout main"
    echo ""
    read -p "Do you REALLY want to continue with 'testing' branch? (yes/no): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Installation cancelled. Switch to main branch:"
        echo "  git checkout main"
        echo "  ./install.sh"
        exit 0
    fi
    echo "⚠️  Proceeding with TESTING branch at your own risk..."
    echo ""
fi

if [ "$EUID" -eq 0 ]; then 
   echo "ERROR: Do not run this script as root!"
   echo "Run as your normal user instead."
   exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PYTHON_DIR="$SCRIPT_DIR/python"
VENV_DIR="$PYTHON_DIR/venv"

detect_package_manager() {
    if command -v apt &> /dev/null; then
        PKG_MANAGER="apt"
        PKG_INSTALL="sudo apt install -y"
        PACKAGES="python3 python3-venv python3-pip libcairo2-dev gtk-layer-shell libgtk-3-0 python3-gi gir1.2-gtk-3.0 pulseaudio-utils fontconfig x11-utils"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="sudo dnf install -y"
        PACKAGES="python3 python3-devel gcc cairo-devel cairo-gobject-devel gtk-layer-shell gtk3 python3-gobject pulseaudio-utils fontconfig xdpyinfo"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        PKG_INSTALL="sudo pacman -S --needed --noconfirm"
        PACKAGES="python cairo gtk-layer-shell gtk3 python-gobject pulseaudio fontconfig xorg-xdpyinfo"
        ARCH_AUDIO_CONFLICT=true
    elif command -v zypper &> /dev/null; then
        PKG_MANAGER="zypper"
        PKG_INSTALL="sudo zypper install -y"
        PACKAGES="python3 python3-devel gcc make pkg-config cairo-devel python3-cairo-devel libgtk-layer-shell0 typelib-1_0-GtkLayerShell-0_1 gtk3 python3-gobject pulseaudio-utils fontconfig xdpyinfo"
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
        echo "  - xdpyinfo or xset (X11 utilities)"
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
    if [ "$ARCH_AUDIO_CONFLICT" = true ]; then
        echo ""
        echo "⚠️  ARCH LINUX DETECTED"
        echo "You may have pipewire-pulse installed, which conflicts with pulseaudio."
        echo ""
        echo "Options:"
        echo "  1) Keep pipewire-pulse (recommended for modern Arch)"
        echo "  2) Switch to pulseaudio"
        echo ""
        read -p "Choose option (1 or 2): " -n 1 -r
        echo ""
        
        if [[ $REPLY == "1" ]]; then
            echo "Using pipewire-pulse (already installed)"
            echo "Removing pulseaudio from package list..."
            sudo pacman -S --needed --noconfirm python gtk-layer-shell gtk3 python-gobject fontconfig xorg-xdpyinfo || {
                echo "WARNING: Some packages failed to install."
                echo "TimeBomb may not work properly without all dependencies."
            }
        else
            echo "Switching to pulseaudio..."
            sudo pacman -S --needed pulseaudio || {
                echo "WARNING: Failed to install pulseaudio."
            }
            sudo pacman -S --needed --noconfirm python gtk-layer-shell gtk3 python-gobject fontconfig xorg-xdpyinfo || {
                echo "WARNING: Some packages failed to install."
            }
        fi
    else
        $PKG_INSTALL $PACKAGES || {
            echo "WARNING: Some packages failed to install."
            echo "TimeBomb may not work properly without all dependencies."
        }
    fi
    echo "✓ System packages installed"
else
    echo "⊘ Skipped system package installation"
    echo "WARNING: Make sure you have all required dependencies installed!"
fi

echo ""
echo "[4/8] Installing DS Digital fonts (required for timer display)..."
FONT_DIR="$HOME/.local/share/fonts"
FONT_SOURCE_DIR="$SCRIPT_DIR/assets/font"

if [ ! -d "$FONT_SOURCE_DIR" ]; then
    echo "ERROR: Font directory not found at $FONT_SOURCE_DIR"
    echo "Please ensure the repository is complete."
    exit 1
fi

mkdir -p "$FONT_DIR"

echo "Copying DS Digital font variants..."
cp "$FONT_SOURCE_DIR"/DS-DIGI*.TTF "$FONT_DIR/" || {
    echo "ERROR: Failed to copy fonts"
    exit 1
}

fc-cache -f "$FONT_DIR" 2>/dev/null
echo "✓ DS Digital fonts installed (regular, bold, italic, thin)"

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
"$VENV_DIR/bin/pip" install evdev PyGObject pyudev || {
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
mkdir -p "$SCRIPT_DIR/assets/logs"
echo "✓ Directories created"

echo ""
echo "======================================"
echo "   Autostart Setup"
echo "======================================"

if [ "$CURRENT_BRANCH" = "testing" ]; then
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║           ⚠️  TESTING BRANCH AUTOSTART WARNING ⚠️          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  You are about to enable autostart for UNSTABLE code!"
    echo ""
    echo "  This means:"
    echo "    - Broken code will run on EVERY login"
    echo "    - Your system may become unstable"
    echo "    - You'll need to manually disable it if it breaks"
    echo ""
    echo "  STRONGLY RECOMMENDED: Do NOT enable autostart on testing branch"
    echo ""
fi

read -p "Do you want TimeBomb to start automatically on login? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    AUTOSTART_DIR="$HOME/.config/autostart"
    DESKTOP_FILE="$AUTOSTART_DIR/timebomb.desktop"
    
    mkdir -p "$AUTOSTART_DIR"
    
    # Increased delay to 20 seconds for more reliable startup
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=TimeBomb
Comment=Floating Timer/Stopwatch
Exec=bash -c "sleep 20 && cd $PYTHON_DIR && $VENV_DIR/bin/python3 $PYTHON_DIR/timebomb.py >> $SCRIPT_DIR/assets/logs/autostart.log 2>&1"
Terminal=false
StartupNotify=false
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=20
Categories=Utility;
Keywords=timer;stopwatch;clock;
EOF

    chmod 644 "$DESKTOP_FILE"
        
    echo "✓ Autostart entry created at: $DESKTOP_FILE"
    echo ""
    echo "TimeBomb will start automatically 20 seconds after login."
    echo "(Increased from 12s to ensure display is ready)"
    echo ""
    echo "To disable autostart later:"
    echo "  rm $DESKTOP_FILE"
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
echo "Enjoy!!"