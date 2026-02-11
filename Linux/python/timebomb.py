#!/usr/bin/env python3
import sys
import time
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

def wait_for_display(logger, max_retries=30, retry_delay=1):
    """Wait for X11 display to be available before importing GTK"""
    logger.info("Waiting for display to be available...")
    
    for i in range(max_retries):
        # Check if DISPLAY environment variable is set
        display_env = os.environ.get('DISPLAY')
        if not display_env:
            logger.warning(f"DISPLAY not set (attempt {i+1}/{max_retries})")
            time.sleep(retry_delay)
            continue
        
        # Try to connect to X server using xset or a simple test
        try:
            import subprocess
            result = subprocess.run(
                ['xset', 'q'],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=2
            )
            if result.returncode == 0:
                logger.info(f"Display available at {display_env} (attempt {i+1}/{max_retries})")
                return True
        except (FileNotFoundError, subprocess.TimeoutExpired):
            # xset not available or timed out, try alternative method
            try:
                # Alternative: try to open a connection using xlib
                import subprocess
                result = subprocess.run(
                    ['xdpyinfo'],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=2
                )
                if result.returncode == 0:
                    logger.info(f"Display available at {display_env} (attempt {i+1}/{max_retries})")
                    return True
            except:
                pass
        except Exception as e:
            logger.debug(f"Display check error: {e}")
        
        logger.info(f"Waiting for display... (attempt {i+1}/{max_retries})")
        time.sleep(retry_delay)
    
    logger.error("Could not connect to display after waiting. No display available?")
    return False

def main():
    logger = setup_logging()
    logger.info("=" * 60)
    logger.info("TimeBomb starting...")
    
    # Wait for display BEFORE importing GTK
    if not wait_for_display(logger):
        logger.error("Failed to connect to display. Exiting.")
        sys.exit(1)
    
    # NOW it's safe to import GTK
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