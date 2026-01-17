# TimeBomb!

A floating stopwatch and timer for Linux and Windows that stays on top of everything - even fullscreen apps. Controlled entirely with Win+key shortcuts.

## What is this?

TimeBomb is a minimal, always-visible timer/stopwatch that floats above your screen. I built it because I needed something that:
- Stays visible during fullscreen games/videos
- Doesn't require clicking around
- Works entirely with keyboard shortcuts
- Doesn't get in the way

It's basically a tiny floating window you can drag anywhere, and it just works.

## Features

- **Stopwatch mode** - counts up from 00:00
- **Timer mode** - counts down from any time you set
- **Always on top** - even over fullscreen apps
- **Keyboard shortcuts** - Win+key combos for quick control
- **Adjustable timer** - hold Win+Up/Down to quickly change timer duration
- **Sound feedback** - satisfying beeps for start/pause/reset
- **Alarm** - loud persistent alarm when timer finishes
- **Remembers position** - window stays where you put it
- **Freezing feature** - hold Win after a keybind to freeze the timer/stopwatch for precise control and flow
- **Cross-platform** - works on both Linux and Windows

## Platform Support

### Linux
- **Tested on:** Fedora KDE Plasma (Wayland/X11)
- **Should work on:** Other distros, but not tested - let me know if you try it!
- Uses GtkLayerShell for proper Wayland overlay support
- Direct keyboard access via evdev

### Windows
- Uses AutoHotkey for system integration
- **Built-in suppression** - Win+key shortcuts won't trigger Windows shortcuts
- **Fewer features** than Linux version (simpler implementation)
- Comes as both `.ahk` (requires AutoHotkey) and `.exe` (standalone)

## Keybinds

All shortcuts use the **Win (Super/Meta)** key:

| Shortcut | Action |
|----------|--------|
| `Win + ` ` | Toggle visibility (show/hide) |
| `Win + Enter` | Pause/Resume |
| `Win + Backspace` | Reset |
| `Win + Esc` | Switch between Timer/Stopwatch |
| `Win + Up` | Increase timer (Timer mode only) |
| `Win + Down` | Decrease timer (Timer mode only) |

### The Freezing Feature

When you perform any keybind (except `Win + Enter`), if you **keep holding the Win key**, the timer/stopwatch will freeze until you release it. This gives you:
- **Precise control** - adjust or reset without losing track of time
- **Flow** - smooth, intentional interactions
- **Feel** - it just *feels* right when you use it

Try it: Press `Win + Grave` to show TimeBomb, then keep Win held - notice how the time freezes? Release Win and it resumes. It's surprisingly addictive.

**Note (Linux only):** These shortcuts might conflict with your system's default keybinds. One workaround is to create a custom shortcut via the system settings, make it execute a command - "true", and assign the conflicting shortcuts to it. This acts as a cheap suppression system. Please do look forward to future updates with built-in suppression.

## Installation

### Linux

**File structure:**
```
Linux/
├── assets/
│   ├── sounds/
│   │   ├── adjust.wav
│   │   ├── alarm.wav
│   │   ├── pause.wav
│   │   ├── play.wav
│   │   ├── reset.wav
│   │   ├── start.wav
│   │   ├── switch_stopwatch.wav
│   │   └── switch_timer.wav
│   └── state/
│       └── state.ini
└── python/
    ├── app_manager.py
    ├── gui.py
    ├── hotkey.py
    ├── stopwatch.py
    ├── timebomb.py
    └── timer.py
```

Dependencies:
- Python 3
- GTK 3
- GtkLayerShell (for Wayland overlay support)
- evdev
- PulseAudio (for sounds)

```bash
# Clone the repo
git clone https://github.com/caffienerd/timebomb.git
cd timebomb

# Make install script executable
chmod +x install.sh

# Run install script
./install.sh
```

The install script handles:
- Installing Python dependencies
- Adding your user to the `input` group (required for keyboard access)
- Setting up autostart (optional)

**Important:** You'll need to log out and back in after installation for the `input` group permissions to take effect.

#### Autostart Configuration (systemd)

If you want TimeBomb to start automatically on login, create a systemd user service:

**Location:** `~/.config/systemd/user/timebomb.service`

```ini
[Unit]
Description=Timebomb Python Script
After=graphical-session.target

[Service]
Environment=GDK_BACKEND=x11
Environment=DISPLAY=:0
WorkingDirectory=%h/_projects/01_python/timebomb/python/
ExecStart=/usr/bin/python3 %h/_projects/01_python/timebomb/python/timebomb.py
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
```

**⚠️ Warning about `RestartSec`:** The restart delay is set to 2 seconds. Setting it too low (like 0.5s) can cause issues if the script crashes repeatedly - systemd might kill it thinking it's misbehaving. 2 seconds is a safe balance.

Enable and start the service:
```bash
systemctl --user enable timebomb.service
systemctl --user start timebomb.service
```

Check status:
```bash
systemctl --user status timebomb.service
```

### Windows

Two options:

**Option 1: Standalone .exe (easiest)**
1. Download `timebomb.exe` from the `windows` folder
2. Double-click to run
3. (Optional) Add to startup:
   - Press `Win + R`, type `shell:startup`, press Enter
   - Create a shortcut to `timebomb.exe` in the startup folder

**Option 2: AutoHotkey script**
1. Install [AutoHotkey](https://www.autohotkey.com/)
2. Download `timebomb.ahk` from the `windows` folder
3. Double-click `timebomb.ahk` to run
4. (Optional) Add to startup folder same as above

**Windows folder structure:**
```
windows/
├── gui_state/
│   └── timebomb_config.ini
├── icon/
│   └── timebomb.ico
├── settings/
│   └── settings.txt
├── sounds/
│   ├── adjust.wav
│   ├── alarm.wav
│   ├── pause.wav
│   ├── play.wav
│   ├── reset.wav
│   ├── start.wav
│   ├── switch_stopwatch.wav
│   └── switch_timer.wav
├── timebomb.ahk
└── timebomb.exe
```

## Uninstallation

### Linux
```bash
chmod +x uninstall.sh
./uninstall.sh
```

### Windows
Just delete the folder. If you added it to startup, remove the shortcut from the startup folder.

## Why "TimeBomb"?

No reason, it's just that the name was available!

## Technical details

### Linux
- Built with GTK 3 and Python
- Uses GtkLayerShell for proper Wayland overlay support
- Direct keyboard access via evdev (no X11 dependencies)
- Threaded keyboard listener to avoid blocking the GUI
- Hot-plug support for USB keyboards

### Windows
- Built with AutoHotkey
- Native Win+key suppression (no conflicts!)
- Simpler implementation than Linux version
- Saves state to INI files

## Known issues

### Linux
- Requires your user to be in the `input` group
- Won't work over certain system modals (lockscreen, etc.)
- Keybinds may conflict with system shortcuts (add custom shortcuts for a cheap workaround as mentioned in the note)
- Only tested on Fedora KDE Plasma - other distros might work but YMMV

### Windows
- None currently - suppression works perfectly!

## TODO

- Built-in keybind suppression system for Linux

## License

MIT - do whatever you want with it

## Contributing

If you find bugs or want features, open an issue. PRs welcome.

Especially interested in hearing if it works on other Linux distros/DEs!