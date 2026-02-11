#timer
from gi.repository import GLib
import time
from datetime import datetime
import os
import subprocess
from gui import AlarmGUI
import logging

class Timer:
    def __init__(self, gui, app_manager):
        self.gui = gui
        self.app_manager = app_manager
        self.running = False
        self.visible = False
        self.paused = False
        self.logger = logging.getLogger(__name__)
        self.logger.info("Initializing timer...")

        # Timer state
        self.timer_minutes = 3
        self.timer_seconds = 0
        self.last_reset_minutes = 3  # Track last reset value
        self.last_reset_seconds = 0
        
        self.timeout_id = None
        self.alarm_gui = None
        self.below_10 = False
        self.blink_source = None
        self.blink_visible = True
        
        # Adjustment state
        self.adjusting_up = False
        self.adjusting_down = False
        self.adjust_start_time = 0
        self.adjust_last_time = 0
        self.adjust_timer_id = None

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
    
    def format_time(self, mins, secs):
        if mins >= 100:
            return f"{mins:03d}:{secs:02d}"
        return f"{mins:02d}:{secs:02d}"
    
    def get_end_time(self):
        """Calculate end time based on current state"""
        # If paused, use displayed time + current time
        if self.paused:
            total_seconds = self.timer_minutes * 60 + self.timer_seconds
            future_time = time.time() + total_seconds
        # If adjusting or Win held after shortcut, use displayed time
        elif self.adjusting_up or self.adjusting_down or (self.app_manager.win_key_held and hasattr(self, 'started_with_win_held') and self.started_with_win_held):
            total_seconds = self.timer_minutes * 60 + self.timer_seconds
            future_time = time.time() + total_seconds
        # If running normally, use precise timer_start_time and total_timer_seconds
        elif hasattr(self, 'timer_start_time') and hasattr(self, 'total_timer_seconds'):
            future_time = self.timer_start_time + self.total_timer_seconds
        # Fallback
        else:
            total_seconds = self.timer_minutes * 60 + self.timer_seconds
            future_time = time.time() + total_seconds
        
        return datetime.fromtimestamp(future_time).strftime("%H:%M:%S")
    
    def start(self, play_sound=True):
        print("[TIMER] Starting timer")
        self.timer_minutes = self.last_reset_minutes
        self.timer_seconds = self.last_reset_seconds
        self.visible = True
        self.running = True
        self.paused = False
        # Track if we started with Win key held (for timer too!)
        self.started_with_win_held = self.app_manager.win_key_held

        self.total_timer_seconds = self.timer_minutes * 60 + self.timer_seconds
        self.timer_start_time = time.time()

        self.gui.set_prefix("Ends at:")
        self.update_display()

        self.gui.show_all()
        self.gui.present()
        self.gui.get_window().raise_()
        self.gui.start_raise_timer()

        if play_sound:
            self.play_sound("start.wav")
        
        # Start the countdown timer
        self.timeout_id = GLib.timeout_add(100, self.tick)
    
    def update_display(self):
        """Update the GUI display"""
        self.gui.set_time(self.format_time(self.timer_minutes, self.timer_seconds))
        self.gui.set_sub_time(self.get_end_time())
    
    def tick(self):
        # Update "Ends at" time even when paused (for display purposes)
        if self.paused:
            self.update_display()
            return True
        
        # Freeze timer if: adjusting OR (started with Win held AND Win is still held)
        is_frozen = (self.adjusting_up or self.adjusting_down or 
                    (self.app_manager.win_key_held and hasattr(self, 'started_with_win_held') and self.started_with_win_held))
        
        if is_frozen:
            # Still update display to keep "Ends at" accurate
            self.update_display()
            return True
        
        if not self.running or not self.visible:
            return False

        # Calculate remaining time based on elapsed time
        elapsed = time.time() - self.timer_start_time
        remaining_total = max(0, self.total_timer_seconds - elapsed)
        
        # Check if timer finished
        if remaining_total <= 0:
            self.running = False
            self.gui.main_label.set_name("main_time_red")
            if self.blink_source:
                GLib.source_remove(self.blink_source)
                self.blink_source = None
            self.gui.main_label.set_opacity(1.0)
            self.trigger_alarm()
            return False
        
        # Convert to minutes and seconds for display
        self.timer_minutes = int(remaining_total // 60)
        self.timer_seconds = int(remaining_total % 60)
        
        # Check for below 10 seconds
        is_below_10 = (self.timer_minutes == 0 and self.timer_seconds <= 10)
        if is_below_10 and not self.below_10:
            self.below_10 = True
            self.gui.main_label.set_name("main_time_red")
            if not self.blink_source:
                self.blink_source = GLib.timeout_add(500, self.blink_timer)
        elif not is_below_10 and self.below_10:
            self.below_10 = False
            self.gui.main_label.set_name("main_time")
            if self.blink_source:
                GLib.source_remove(self.blink_source)
                self.blink_source = None
            self.gui.main_label.set_opacity(1.0)

        self.update_display()
        return True
    
    def trigger_alarm(self):
        """Show alarm GUI when timer completes"""
        self.alarm_gui = AlarmGUI(on_dismiss=self.on_alarm_dismiss, on_reset=self.on_alarm_reset)
        self.alarm_gui.show_all()
        self.alarm_gui.present()
        self.alarm_gui.start_alarm_loop()
        self.play_sound("alarm.wav")
    
    def on_alarm_dismiss(self):
        """Handle alarm dismissal (Done button)"""
        self.alarm_gui = None
        self.stop()
    
    def on_alarm_reset(self):
        """Handle alarm reset (Reset button)"""
        self.alarm_gui = None
        
        # Clean up any existing timers
        if self.timeout_id:
            GLib.source_remove(self.timeout_id)
            self.timeout_id = None
        if self.blink_source:
            GLib.source_remove(self.blink_source)
            self.blink_source = None
        
        # Reset to last reset value
        self.timer_minutes = self.last_reset_minutes
        self.timer_seconds = self.last_reset_seconds
        self.total_timer_seconds = self.timer_minutes * 60 + self.timer_seconds
        self.timer_start_time = time.time()
        
        # Set running state
        self.running = True
        self.paused = False
        self.below_10 = False
        self.started_with_win_held = False
        
        # Reset visual state
        self.gui.main_label.set_name("main_time")
        self.gui.main_label.set_opacity(1.0)
        
        # Update display
        self.update_display()
        
        # Start the tick timer
        self.timeout_id = GLib.timeout_add(100, self.tick)
        
        # Play reset sound (not start sound)
        self.play_sound("reset.wav")
    
    def stop(self):
        print("[TIMER] Stopping timer")
        if self.timeout_id:
            try:
                GLib.source_remove(self.timeout_id)
            except (ValueError, AttributeError):
                pass
            self.timeout_id = None
        if self.blink_source:
            try:
                GLib.source_remove(self.blink_source)
            except (ValueError, AttributeError):
                pass
            self.blink_source = None
        if self.adjust_timer_id:
            try:
                GLib.source_remove(self.adjust_timer_id)
            except (ValueError, AttributeError):
                pass
            self.adjust_timer_id = None
        
        self.running = False
        self.visible = False
        self.below_10 = False
        self.adjusting_up = False
        self.adjusting_down = False
        self.gui.main_label.set_name("main_time")
        self.gui.main_label.set_opacity(1.0)
        self.gui.hide()
        
        # Reset to default 3:00 when timer is unloaded
        self.last_reset_minutes = 3
        self.last_reset_seconds = 0
        print("[TIMER] Reset value cleared - back to default 3:00")

    def blink_timer(self):
        """Blink the time display when paused OR when below 10 seconds"""
        # Handle paused state blinking
        if self.paused:
            self.blink_visible = not self.blink_visible
            self.gui.main_label.set_opacity(1.0 if self.blink_visible else 0.0)
            return True
        
        # Handle below 10 seconds blinking (only when running)
        if not self.below_10 or not self.running:
            return False

        self.blink_visible = not self.blink_visible
        new_name = "main_time_red" if self.blink_visible else "main_time"
        self.gui.main_label.set_name(new_name)
        return True

    def adjust_up_start(self):
        """Start adjusting timer up"""
        if not self.visible or self.paused:
            return
        
        print("[TIMER] Adjust UP started")
        self.adjusting_up = True
        self.adjust_start_time = time.time()
        self.adjust_last_time = time.time()
        
        # Set seconds to 00 immediately
        self.timer_seconds = 0
        
        # Do first adjustment
        if self.timer_minutes < 999:
            self.timer_minutes += 1
            self.play_sound("adjust.wav")
            self.update_display()
        
        # Start adjustment timer for acceleration
        self.adjust_timer_id = GLib.timeout_add(50, self.adjust_up_tick)
    
    def adjust_up_tick(self):
        """Adjustment timer callback for UP"""
        if not self.adjusting_up:
            return False
        
        # Calculate hold duration
        hold_time = time.time() - self.adjust_start_time
        
        # Determine delay based on hold time
        if hold_time < 0.35:
            delay = 0.25
        elif hold_time < 0.9:
            delay = 0.12
        elif hold_time < 1.5:
            delay = 0.04
        elif hold_time < 2.0:
            delay = 0.02
        else:
            delay = 0.001
        
        # Check if enough time has passed
        if time.time() - self.adjust_last_time >= delay:
            if self.timer_minutes < 999:
                self.timer_minutes += 1
                self.timer_seconds = 0
                self.update_display()
                self.adjust_last_time = time.time()
        
        return True
    
    def adjust_up_stop(self):
        """Stop adjusting timer up"""
        if not self.adjusting_up:
            return
        
        print("[TIMER] Adjust UP stopped")
        self.adjusting_up = False
        
        if self.adjust_timer_id:
            GLib.source_remove(self.adjust_timer_id)
            self.adjust_timer_id = None
        
        # Update timer base with new values
        self.total_timer_seconds = self.timer_minutes * 60 + self.timer_seconds
        self.timer_start_time = time.time()
        
        # Save as last reset value
        self.last_reset_minutes = self.timer_minutes
        self.last_reset_seconds = self.timer_seconds
        
        # If Win key is held, mark that we should stay frozen
        if self.app_manager.win_key_held:
            print("[TIMER] Win key still held after adjustment - staying frozen")
            self.started_with_win_held = True
        else:
            print("[TIMER] Resuming after adjustment (Win not held)")
            self.running = True
            self.started_with_win_held = False

    def adjust_down_start(self):
        """Start adjusting timer down"""
        if not self.visible or self.paused:
            return
        
        # FIXED: Check minimum time before allowing adjustment
        total_seconds = self.timer_minutes * 60 + self.timer_seconds
        if total_seconds <= 60:  # Don't allow going below 1:00
            print("[TIMER] Cannot adjust below 01:00 - adjustment blocked")
            return
        
        print("[TIMER] Adjust DOWN started")
        self.adjusting_down = True
        self.adjust_start_time = time.time()
        self.adjust_last_time = time.time()
        
        # Set seconds to 00 immediately
        self.timer_seconds = 0
        
        # Do first adjustment - with safety check
        if self.timer_minutes > 1:
            self.timer_minutes -= 1
            self.play_sound("adjust.wav")
            self.update_display()
        
        # Start adjustment timer for acceleration
        self.adjust_timer_id = GLib.timeout_add(50, self.adjust_down_tick)
    
    def adjust_down_tick(self):
        """Adjustment timer callback for DOWN"""
        if not self.adjusting_down:
            return False
        
        # Calculate hold duration
        hold_time = time.time() - self.adjust_start_time
        
        # Determine delay based on hold time
        if hold_time < 0.35:
            delay = 0.25
        elif hold_time < 0.9:
            delay = 0.12
        elif hold_time < 1.5:
            delay = 0.04
        elif hold_time < 2.0:
            delay = 0.02
        else:
            delay = 0.001
        
        # Check if enough time has passed
        if time.time() - self.adjust_last_time >= delay:
            # FIXED: Don't go below 1 minute
            if self.timer_minutes > 1:
                self.timer_minutes -= 1
                self.timer_seconds = 0
                self.update_display()
                self.adjust_last_time = time.time()
        
        return True
    
    def adjust_down_stop(self):
        """Stop adjusting timer down"""
        if not self.adjusting_down:
            return
        
        print("[TIMER] Adjust DOWN stopped")
        self.adjusting_down = False
        
        if self.adjust_timer_id:
            GLib.source_remove(self.adjust_timer_id)
            self.adjust_timer_id = None
        
        # Update timer base with new values
        self.total_timer_seconds = self.timer_minutes * 60 + self.timer_seconds
        self.timer_start_time = time.time()
        
        # Save as last reset value
        self.last_reset_minutes = self.timer_minutes
        self.last_reset_seconds = self.timer_seconds
        
        # If Win key is held, mark that we should stay frozen
        if self.app_manager.win_key_held:
            print("[TIMER] Win key still held after adjustment - staying frozen")
            self.started_with_win_held = True
        else:
            print("[TIMER] Resuming after adjustment (Win not held)")
            self.running = True
            self.started_with_win_held = False

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
            
            # Recalculate timer base from current displayed time
            self.total_timer_seconds = self.timer_minutes * 60 + self.timer_seconds
            self.timer_start_time = time.time()
            
            # If Win key is held during unpause, mark it so we stay frozen
            if self.app_manager.win_key_held:
                print("[TIMER] Win key held during unpause - will stay frozen")
                self.started_with_win_held = True
            else:
                self.started_with_win_held = False
            
            # Restart the tick timer
            if not self.timeout_id:
                self.timeout_id = GLib.timeout_add(100, self.tick)
            
            self.play_sound("play.wav")
        else:
            # PAUSING - no freeze behavior needed
            self.paused = True
            self.running = False
            
            # DON'T stop the tick timer - we need it to update "Ends at"
            # Just let tick() handle the paused state
            
            self.blink_source = GLib.timeout_add(500, self.blink_timer)
            
            self.play_sound("pause.wav")

    def reset(self):
        if not self.visible:
            return
        
        print("[TIMER] Resetting timer")
        
        was_running = self.running and not self.paused
        was_paused = self.paused
        
        # Stop all timers
        if self.timeout_id:
            GLib.source_remove(self.timeout_id)
            self.timeout_id = None
        if self.blink_source:
            GLib.source_remove(self.blink_source)
            self.blink_source = None
        if self.adjust_timer_id:
            GLib.source_remove(self.adjust_timer_id)
            self.adjust_timer_id = None
        
        # Reset to last reset value
        self.timer_minutes = self.last_reset_minutes
        self.timer_seconds = self.last_reset_seconds
        self.total_timer_seconds = self.timer_minutes * 60 + self.timer_seconds
        self.timer_start_time = time.time()
        
        # Reset visual state
        self.gui.main_label.set_name("main_time")
        self.gui.main_label.set_opacity(1.0)
        self.below_10 = False
        self.adjusting_up = False
        self.adjusting_down = False
        
        # Update display
        self.update_display()
        
        # If Win key is held during reset, mark it so we stay frozen
        if self.app_manager.win_key_held:
            print("[TIMER] Win key held during reset - will stay frozen")
            self.started_with_win_held = True
        else:
            self.started_with_win_held = False
        
        # Restore the running/paused state
        if was_paused:
            self.paused = True
            self.running = False
            self.blink_source = GLib.timeout_add(500, self.blink_timer)
        elif was_running:
            self.paused = False
            self.running = True
        
        # Always restart the tick timer
        self.timeout_id = GLib.timeout_add(100, self.tick)
        
        self.play_sound("reset.wav")