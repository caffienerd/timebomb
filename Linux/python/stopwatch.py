#stopwatch
from gi.repository import GLib
import time
from datetime import datetime
import os
import subprocess

class Stopwatch:
    def __init__(self, gui, app_manager):
        self.gui = gui
        self.app_manager = app_manager
        self.running = False
        self.paused = False
        self.visible = False
        self.start_time = None
        self.elapsed_seconds = 0
        self.update_source = None
        self.blink_source = None
        self.blink_visible = True
        
        # Sound directory
        base_dir = os.path.dirname(os.path.dirname(__file__))
        self.sound_dir = os.path.join(base_dir, "assets", "sounds")
        
    def play_sound(self, filename):
        """Play a sound file"""
        sound_path = os.path.join(self.sound_dir, filename)
        if os.path.exists(sound_path):
            try:
                subprocess.Popen(['paplay', sound_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except:
                pass
        
    def format_time(self, total_seconds):
        mins = int(total_seconds // 60)
        secs = int(total_seconds % 60)
        if mins >= 100:
            return f"{mins:03d}:{secs:02d}"
        return f"{mins:02d}:{secs:02d}"
    
    def start(self, play_sound=True):
        self.visible = True
        self.paused = False
        self.elapsed_seconds = 0
        # Track if we started with Win key held (STOPWATCH ONLY)
        self.started_with_win_held = self.app_manager.win_key_held
        # Track that this is a fresh launch (for dynamic "Started:" time)
        self.fresh_launch = True

        self.gui.set_prefix("Started:")
        self.gui.set_time("00:00")
        self.gui.set_sub_time(datetime.now().strftime("%H:%M:%S"))

        self.gui.show_all()
        self.gui.present()
        self.gui.get_window().raise_()

        self.gui.start_raise_timer()

        # ALWAYS start the timer immediately when launched
        self.running = True
        self.start_time = time.time()
        self.update_source = GLib.timeout_add(100, self.tick)

        if play_sound:
            self.play_sound("start.wav")
    
    def stop(self):
        self.visible = False
        self.running = False
        self.paused = False
        
        if self.update_source:
            try:
                GLib.source_remove(self.update_source)
            except (ValueError, AttributeError):
                pass
            self.update_source = None
        
        if self.blink_source:
            try:
                GLib.source_remove(self.blink_source)
            except (ValueError, AttributeError):
                pass
            self.blink_source = None
        
        self.gui.hide()
    
    def pause_toggle(self):
        if not self.visible:
            return
        
        if self.paused:
            # UNPAUSING
            self.paused = False
            self.running = True
            
            if self.blink_source:
                GLib.source_remove(self.blink_source)
                self.blink_source = None
            self.blink_visible = True
            self.gui.main_label.set_opacity(1.0)
            
            self.start_time = time.time() - self.elapsed_seconds
            self.update_source = GLib.timeout_add(100, self.tick)
            
            # If Win key is held during unpause, mark it so we stay frozen
            if self.app_manager.win_key_held:
                print("[STOPWATCH] Win key held during unpause - will stay frozen")
                self.started_with_win_held = True
                # Do NOT set fresh_launch for unpause - "Started:" should stay fixed
                self.fresh_launch = False
            else:
                self.started_with_win_held = False
                self.fresh_launch = False
            
            self.play_sound("play.wav")
        else:
            # PAUSING - no freeze behavior needed
            self.paused = True
            self.running = False
            
            if self.update_source:
                GLib.source_remove(self.update_source)
                self.update_source = None
            
            self.blink_source = GLib.timeout_add(500, self.blink)
            
            self.play_sound("pause.wav")
    
    def blink(self):
        """Blink the time display when paused"""
        if not self.paused:
            return False
        
        self.blink_visible = not self.blink_visible
        self.gui.main_label.set_opacity(1.0 if self.blink_visible else 0.0)
        return True
    
    def reset(self):
        if not self.visible:
            return
        
        was_running = self.running and not self.paused
        was_paused = self.paused
        
        if self.update_source:
            GLib.source_remove(self.update_source)
            self.update_source = None
        if self.blink_source:
            GLib.source_remove(self.blink_source)
            self.blink_source = None
        
        self.elapsed_seconds = 0
        self.start_time = time.time()
        self.gui.set_time("00:00")
        self.gui.main_label.set_opacity(1.0)
        
        # Update "Started:" time on reset
        self.gui.set_sub_time(datetime.now().strftime("%H:%M:%S"))
        
        # If Win key is held during reset, mark it so we stay frozen
        if self.app_manager.win_key_held:
            print("[STOPWATCH] Win key held during reset - will stay frozen")
            self.started_with_win_held = True
            # Mark as fresh launch for dynamic "Started:" time
            self.fresh_launch = True
        else:
            self.started_with_win_held = False
            self.fresh_launch = False
        
        if was_paused:
            self.paused = True
            self.running = False
            self.blink_source = GLib.timeout_add(500, self.blink)
        elif was_running:
            self.paused = False
            self.running = True
            self.update_source = GLib.timeout_add(100, self.tick)
        
        self.play_sound("reset.wav")
    
    def tick(self):
        # Freeze the timer only if we started WITH Win key held (STOPWATCH ONLY)
        if self.app_manager.win_key_held and self.started_with_win_held:
            # Update "Started:" time dynamically if this is a fresh launch
            if self.fresh_launch:
                self.gui.set_sub_time(datetime.now().strftime("%H:%M:%S"))
            
            # Still update the display with frozen time
            if self.running and not self.paused:
                self.gui.set_time(self.format_time(self.elapsed_seconds))
            return True  # Keep the timer alive but frozen

        if not self.running or self.paused:
            return False

        self.elapsed_seconds = time.time() - self.start_time
        self.gui.set_time(self.format_time(self.elapsed_seconds))
        return True