#app_manager
from gi.repository import GLib, Gdk
import os
import time
import configparser
import subprocess
from stopwatch import Stopwatch
from timer import Timer # type: ignore

class AppManager:
    def __init__(self, gui):
        self.gui = gui
        self.stopwatch = Stopwatch(gui, self)
        self.timer = Timer(gui, self)
        self.mode = "stopwatch"
        
        # Get config file path relative to script location
        base_dir = os.path.dirname(os.path.dirname(__file__))
        self.config_file = os.path.join(base_dir, "assets", "state", "state.ini")
        
        # CRITICAL: Win key held state
        self.win_key_held = False
        self.shortcut_executed = False
        
        os.makedirs(os.path.dirname(self.config_file), exist_ok=True)
        
        self.gui.save_callback = self.save_state
        
        self.load_state()
    
    def get_current(self):
        """Get the current active mode instance"""
        return self.stopwatch if self.mode == "stopwatch" else self.timer
    
    def toggle(self):
        """Toggle visibility of current mode"""
        current = self.get_current()
        
        # Special handling for timer alarm
        if self.mode == "timer" and hasattr(self.timer, 'alarm_gui') and self.timer.alarm_gui:
            print("[APP] Alarm active - Win+` dismisses alarm and closes timer")
            self.timer.alarm_gui.dismiss()
            return
        
        if current.visible:
            self.save_state()
            current.stop()
        else:
            self.load_state()
            current.start()
    
    def pause(self):
        """Pause/resume current mode"""
        # Block if timer alarm is active
        if self.mode == "timer" and hasattr(self.timer, 'alarm_gui') and self.timer.alarm_gui:
            print("[APP] Alarm active - Win+Enter blocked")
            return
        
        self.get_current().pause_toggle()
    
    def reset(self):
        """Reset current mode"""
        # Special handling for timer alarm
        if self.mode == "timer" and hasattr(self.timer, 'alarm_gui') and self.timer.alarm_gui:
            print("[APP] Alarm active - Win+Backspace resets and dismisses alarm")
            self.timer.alarm_gui.reset_and_dismiss()
            return
        
        self.get_current().reset()
    
    def switch_mode(self):
        """Switch between timer and stopwatch"""
        # Block if timer alarm is active
        if self.mode == "timer" and hasattr(self.timer, 'alarm_gui') and self.timer.alarm_gui:
            print("[APP] Alarm active - Win+Esc blocked")
            return
        
        was_visible = self.get_current().visible

        if was_visible:
            self.save_state()
            # Clean up ALL timers from current mode
            current = self.get_current()
            
            # Remove timeout_id
            if hasattr(current, 'timeout_id') and current.timeout_id:
                GLib.source_remove(current.timeout_id)
                current.timeout_id = None
            
            # Remove update_source
            if hasattr(current, 'update_source') and current.update_source:
                GLib.source_remove(current.update_source)
                current.update_source = None
            
            # FIX: Remove blink_source (THIS WAS MISSING!)
            if hasattr(current, 'blink_source') and current.blink_source:
                GLib.source_remove(current.blink_source)
                current.blink_source = None
            
            # Reset visual state
            current.running = False
            current.visible = False
            current.gui.main_label.set_opacity(1.0)  # Reset opacity
            current.gui.main_label.set_name("main_time")  # Reset CSS class (fixes red color carry-over)

        # Reset timer's last reset value when switching away from timer mode
        if self.mode == "timer":
            print("[APP] Switching away from timer - resetting last reset value to 3:00")
            self.timer.last_reset_minutes = 3
            self.timer.last_reset_seconds = 0

        self.mode = "timer" if self.mode == "stopwatch" else "stopwatch"

        self.save_state()

        sound_file = "switch_timer.wav" if self.mode == "timer" else "switch_stopwatch.wav"
        base_dir = os.path.dirname(os.path.dirname(__file__))
        sound_path = os.path.join(base_dir, "assets", "sounds", sound_file)
        if os.path.exists(sound_path):
            try:
                subprocess.Popen(['paplay', sound_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except:
                pass

        if was_visible:
            self.load_state()
            self.get_current().start(play_sound=False)
    
    def on_win_key_release(self):
        """Called when Win key is released"""
        print(f"[APP] Win key RELEASED - win_key_held was {self.win_key_held}")
        self.win_key_held = False
        self.shortcut_executed = False

        # For stopwatch: update start time to account for frozen period
        if self.mode == "stopwatch":
            if self.stopwatch.visible and self.stopwatch.running and not self.stopwatch.paused:
                # Only adjust if we started with Win held
                if hasattr(self.stopwatch, 'started_with_win_held') and self.stopwatch.started_with_win_held:
                    print("[APP] Adjusting stopwatch start time after Win key release")
                    self.stopwatch.start_time = time.time() - self.stopwatch.elapsed_seconds
                    self.stopwatch.started_with_win_held = False
                    # Clear fresh_launch flag so "Started:" stops updating
                    if hasattr(self.stopwatch, 'fresh_launch'):
                        self.stopwatch.fresh_launch = False

        # For timer: resume if it was frozen
        if self.mode == "timer":
            if self.timer.visible and not self.timer.paused:
                # Only resume if we started with Win held AND not adjusting
                if (hasattr(self.timer, 'started_with_win_held') and self.timer.started_with_win_held and 
                    not self.timer.adjusting_up and not self.timer.adjusting_down):
                    print("[APP] Resuming timer after Win key release")
                    # Recalculate the timer base
                    self.timer.total_timer_seconds = self.timer.timer_minutes * 60 + self.timer.timer_seconds
                    self.timer.timer_start_time = time.time()
                    self.timer.running = True
                    self.timer.started_with_win_held = False
    
    def get_screen_center(self):
        """Get the center position for the window on the current screen"""
        # Get screen dimensions
        display = Gdk.Display.get_default()
        monitor = display.get_primary_monitor()
        if not monitor:
            # Fallback: get first monitor
            monitor = display.get_monitor(0)
        
        geometry = monitor.get_geometry()
        screen_width = geometry.width
        screen_height = geometry.height
        
        # Get window size (estimated - window might not be realized yet)
        window_width = 180
        window_height = 85
        
        # Calculate center position
        center_x = (screen_width - window_width) // 2
        center_y = (screen_height - window_height) // 2
        
        return center_x, center_y
    
    def is_position_valid(self, x, y):
        """Check if a position is valid for the current screen"""
        # Get screen dimensions
        display = Gdk.Display.get_default()
        monitor = display.get_primary_monitor()
        if not monitor:
            monitor = display.get_monitor(0)
        
        geometry = monitor.get_geometry()
        screen_x = geometry.x
        screen_y = geometry.y
        screen_width = geometry.width
        screen_height = geometry.height
        
        # Window size (estimated)
        window_width = 180
        window_height = 85
        
        # Check if position is completely off-screen
        if x < screen_x or y < screen_y:
            return False
        if x + window_width > screen_x + screen_width:
            return False
        if y + window_height > screen_y + screen_height:
            return False
        
        return True
    
    def save_state(self):
        """Save mode and GUI position to config file"""
        config = configparser.ConfigParser()

        if os.path.exists(self.config_file):
            config.read(self.config_file)

        if 'General' not in config:
            config['General'] = {}
        config['General']['mode'] = self.mode

        x, y = self.gui.get_position()
        if 'Position' not in config:
            config['Position'] = {}
        config['Position']['x'] = str(x)
        config['Position']['y'] = str(y)

        with open(self.config_file, 'w') as f:
            config.write(f)
    
    def load_state(self):
        """Load mode and GUI position from config file"""
        # Default position (will be calculated if needed)
        default_x, default_y = None, None
        
        if not os.path.exists(self.config_file):
            # No config file - use center of screen
            default_x, default_y = self.get_screen_center()
            print(f"[APP] No state file - using screen center: ({default_x}, {default_y})")
            self.gui.move(default_x, default_y)
            return

        config = configparser.ConfigParser()
        config.read(self.config_file)

        if 'General' in config and 'mode' in config['General']:
            self.mode = config['General']['mode']

        if 'Position' in config:
            try:
                x = int(config['Position'].get('x', 200))
                y = int(config['Position'].get('y', 200))
                
                # Validate position
                if self.is_position_valid(x, y):
                    print(f"[APP] Loaded valid position: ({x}, {y})")
                    self.gui.move(x, y)
                else:
                    # Position is invalid - use center
                    if default_x is None:
                        default_x, default_y = self.get_screen_center()
                    print(f"[APP] Position ({x}, {y}) is off-screen - using center: ({default_x}, {default_y})")
                    self.gui.move(default_x, default_y)
                    # Save the new valid position
                    self.save_state()
            except (ValueError, TypeError) as e:
                # Invalid position data - use center
                if default_x is None:
                    default_x, default_y = self.get_screen_center()
                print(f"[APP] Invalid position data - using center: ({default_x}, {default_y})")
                self.gui.move(default_x, default_y)
                self.save_state()
        else:
            # No position saved - use center
            if default_x is None:
                default_x, default_y = self.get_screen_center()
            print(f"[APP] No position in config - using center: ({default_x}, {default_y})")
            self.gui.move(default_x, default_y)
            self.save_state()