#!/usr/bin/env python3
import argparse
import sys
import logging
import os
import socket
import threading
from pathlib import Path
from datetime import datetime

# Choose GTK backend before importing Gtk. Prefer native Wayland so
# GtkLayerShell can work, but allow X11 fallback and user overrides.
os.environ.setdefault('GDK_BACKEND', 'wayland,x11')


def get_control_socket_path():
    """Return the per-user socket used by launcher shortcuts."""
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime_dir:
        user_runtime_dir = Path("/run/user") / str(os.getuid())
        if user_runtime_dir.is_dir():
            runtime_dir = str(user_runtime_dir)
    if runtime_dir:
        return Path(runtime_dir) / "timebomb.sock"
    return Path.home() / ".cache" / "timebomb" / "timebomb.sock"


def send_control_command(command, timeout=1.0):
    """Send a command to the running TimeBomb instance."""
    socket_path = get_control_socket_path()
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(timeout)
            client.connect(str(socket_path))
            client.sendall(f"{command}\n".encode("utf-8"))
            response = client.recv(128).decode("utf-8", errors="replace").strip()
            return response == "ok"
    except OSError:
        return False


class ControlServer:
    """Small local command server for desktop launchers."""
    def __init__(self, app_manager, glib, logger):
        self.app_manager = app_manager
        self.glib = glib
        self.logger = logger
        self.socket_path = get_control_socket_path()
        self.server = None
        self.running = False
        self.thread = None

    def start(self):
        self.socket_path.parent.mkdir(parents=True, exist_ok=True)
        if self.socket_path.exists():
            if send_control_command("ping", timeout=0.2):
                raise RuntimeError(f"TimeBomb is already running at {self.socket_path}")
            self.socket_path.unlink()

        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.settimeout(0.5)
        self.server.bind(str(self.socket_path))
        self.server.listen(4)
        self.running = True
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()
        self.logger.info(f"Control socket listening at {self.socket_path}")

    def stop(self):
        self.running = False
        if self.server:
            try:
                self.server.close()
            except OSError:
                pass
            self.server = None

        try:
            if self.socket_path.exists():
                self.socket_path.unlink()
        except OSError as e:
            self.logger.warning(f"Could not remove control socket: {e}")

    def _serve(self):
        while self.running:
            try:
                conn, _ = self.server.accept()
            except socket.timeout:
                continue
            except OSError:
                break

            with conn:
                try:
                    command = conn.recv(128).decode("utf-8", errors="replace").strip().lower()
                    ok = self._handle_command(command)
                    conn.sendall(b"ok\n" if ok else b"unknown\n")
                except OSError as e:
                    self.logger.warning(f"Control socket error: {e}")

    def _handle_command(self, command):
        if command == "ping":
            return True

        actions = {
            "show": self.app_manager.show,
            "hide": self.app_manager.hide,
            "toggle": self.app_manager.toggle,
        }
        action = actions.get(command)
        if not action:
            return False

        def run_action():
            action()
            return False

        self.glib.idle_add(run_action)
        self.logger.info(f"Queued control command: {command}")
        return True


def parse_args():
    parser = argparse.ArgumentParser(description="TimeBomb floating timer/stopwatch")
    command_group = parser.add_mutually_exclusive_group()
    command_group.add_argument("--show", action="store_true", help="show the running TimeBomb window")
    command_group.add_argument("--hide", action="store_true", help="hide the running TimeBomb window")
    command_group.add_argument("--toggle", action="store_true", help="toggle the running TimeBomb window")
    command_group.add_argument("--ping", action="store_true", help="check whether TimeBomb is already running")
    return parser.parse_args()

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
    args = parse_args()
    command = None
    if args.show:
        command = "show"
    elif args.hide:
        command = "hide"
    elif args.toggle:
        command = "toggle"
    elif args.ping:
        command = "ping"

    if command:
        sys.exit(0 if send_control_command(command) else 1)

    logger = setup_logging()
    logger.info("=" * 60)
    logger.info("TimeBomb starting...")
    
    # Import GTK (systemd ensures display is ready)
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk, Gdk, GLib
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
    control_server = None
    
    try:
        gui = AppGUI()
        app_manager = AppManager(gui)
        control_server = ControlServer(app_manager, GLib, logger)
        control_server.start()
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
            if control_server:
                control_server.stop()
            if hotkeys:
                hotkeys.stop()
            if app_manager:
                app_manager.save_state()
            logger.info("TimeBomb shut down cleanly")
        except Exception as e:
            logger.exception(f"Error during shutdown: {e}")

if __name__ == "__main__":
    main()
