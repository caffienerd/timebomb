#!/usr/bin/env python3
import gi
import sys
import time
import logging
from pathlib import Path
from datetime import datetime

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

from gui import AppGUI
from app_manager import AppManager
from hotkey import HotkeyManager

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
    
    # Wait for display to be available (useful on autostart)
    max_retries = 20  # Increased from 10
    retry_delay = 1
    
    for i in range(max_retries):
        if Gtk.init_check(sys.argv):
            logger.info(f"GTK initialized successfully (attempt {i+1}/{max_retries})")
            break
        logger.warning(f"Waiting for display... ({i+1}/{max_retries})")
        time.sleep(retry_delay)
    else:
        logger.error("Could not initialize GTK after waiting. No display available?")
        sys.exit(1)
    
    # Initialize components (declare variables first to avoid UnboundLocalError)
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