#!/usr/bin/env python3
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

from gui import AppGUI
from app_manager import AppManager
from hotkey import HotkeyManager

def main():
    gui = AppGUI()
    app_manager = AppManager(gui)
    hotkeys = HotkeyManager(app_manager)
    
    if not hotkeys.start():
        print("Warning: No keyboards found, but will keep scanning for devices...")
    
    print("TimeBomb started successfully!")
    print(f"Current mode: {app_manager.mode}")
    
    try:
        Gtk.main()
    except KeyboardInterrupt:
        pass
    finally:
        hotkeys.stop()
        app_manager.save_state()

if __name__ == "__main__":
    main()