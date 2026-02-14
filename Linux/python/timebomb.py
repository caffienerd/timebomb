#!/usr/bin/env python3
import sys
import logging
import os
from pathlib import Path
from datetime import datetime

# Force X11 backend - MUST be before importing Gtk
os.environ['GDK_BACKEND'] = 'x11'

def setup_logging():
    """Setup logging to file and console"""
    # Get script directory and create logs folder
    script_dir = Path(__file__).parent.parent
    log_dir = script_dir / "assets" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    
    # Create log filename with timestamp
    log_file = log_dir / f"timebomb_{datetime.now().strftime('%Y%m%d')}.log"
    
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler(sys.stdout)  # Also print to console
        ]
    )
    
    # Clean up old logs (keep last 30 days)
    cleanup_old_logs(log_dir, days=30)
    
    return logging.getLogger(__name__)

def cleanup_old_logs(log_dir, days=30):
    """Remove log files older than specified days"""
    try:
        cutoff = datetime.now().timestamp() - (days * 86400)
        for log_file in log_dir.glob("timebomb_*.log"):
            if log_file.stat().st_mtime < cutoff:
                log_file.unlink()
                print(f"Deleted old log: {log_file.name}")
    except Exception as e:
        print(f"Warning: Could not clean up old logs: {e}")

def main():
    logger = setup_logging()
    logger.info("=" * 60)
    logger.info("TimeBomb starting...")
    
    # Import GTK (systemd ensures display is ready)
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk, Gdk
        logger.info("GTK imported successfully")
    except Exception as e:
        logger.error(f"Failed to import GTK: {e}")
        sys.exit(1)
    
    # Verify GTK can initialize
    try:
        if not Gtk.init_check(None)[0]:
            logger.error("GTK initialization check failed")
            sys.exit(1)
        logger.info("GTK initialized successfully")
    except Exception as e:
        logger.error(f"GTK initialization error: {e}")
        sys.exit(1)
    
    # Verify display is accessible
    try:
        display = Gdk.Display.get_default()
        if display is None:
            logger.error("No default display available")
            sys.exit(1)
        logger.info(f"Display available: {display.get_name()}")
    except Exception as e:
        logger.error(f"Failed to get display: {e}")
        sys.exit(1)
    
    # Import application modules (after GTK is ready)
    from gui import AppGUI
    from app_manager import AppManager
    from hotkey import HotkeyManager
    
    # Initialize components
    gui = None
    app_manager = None
    hotkeys = None
    
    try:
        gui = AppGUI()
        app_manager = AppManager(gui)
        hotkeys = HotkeyManager(app_manager)
        
        if not hotkeys.start():
            logger.warning("No keyboards found, but will keep scanning for devices...")
        
        logger.info("TimeBomb started successfully!")
        logger.info(f"Current mode: {app_manager.mode}")
        
        Gtk.main()
        
    except Exception as e:
        logger.exception(f"Fatal error in main: {e}")
        sys.exit(1)
    finally:
        try:
            if hotkeys:
                hotkeys.stop()
            if app_manager:
                app_manager.save_state()
            logger.info("TimeBomb shut down cleanly")
        except Exception as e:
            logger.exception(f"Error during shutdown: {e}")

if __name__ == "__main__":
    main()