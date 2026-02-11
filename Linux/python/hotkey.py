#hotkey
from gi.repository import GLib
import evdev
from evdev import ecodes
import select
import threading
import time
import queue
import logging


class HotkeyManager:
    def __init__(self, app_manager):
        self.logger = logging.getLogger(__name__)
        self.logger.info("Initializing hotkey manager..")
        self.app_manager = app_manager
        self.devices = {}  # Changed to dict: path -> device
        self.running = False
        self.up_key_held = False
        self.down_key_held = False
        self.win_key_pressed = False
        
        # NEW: Track other modifier keys
        self.other_modifiers = set()
        
        # Define other modifier keys
        self.modifier_keys = {
            ecodes.KEY_LEFTCTRL, ecodes.KEY_RIGHTCTRL,
            ecodes.KEY_LEFTSHIFT, ecodes.KEY_RIGHTSHIFT,
            ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT
        }
        
        # Track non-combo keys pressed while Win is held
        self.non_combo_keys_pressed = set()
        
        # Define combo keys for easy reference
        self.combo_keys = {
            ecodes.KEY_GRAVE,
            ecodes.KEY_ENTER,
            ecodes.KEY_BACKSPACE,
            ecodes.KEY_ESC,
            ecodes.KEY_UP,
            ecodes.KEY_DOWN
        }
        
        # Queue for thread-safe device updates
        self.device_queue = queue.Queue()
        self.scan_thread = None
        
    def find_keyboards(self):
        """Find all keyboard devices"""
        keyboards = {}
        
        try:
            for path in evdev.list_devices():
                try:
                    device = evdev.InputDevice(path)
                    caps = device.capabilities()
                    
                    if ecodes.EV_KEY in caps:
                        keys = caps[ecodes.EV_KEY]
                        if ecodes.KEY_A in keys and ecodes.KEY_Z in keys:
                            keyboards[path] = device
                            print(f"[HOTKEY] Found keyboard: {device.name} at {path}")
                except Exception:
                    # Skip devices we can't access
                    pass
        except Exception as e:
            print(f"[HOTKEY] Error scanning devices: {e}")
        
        return keyboards
    
    def scan_thread_worker(self):
        """Background thread for device scanning - doesn't block main thread!"""
        while self.running:
            try:
                # Scan for keyboards (this is the blocking part)
                current_keyboards = self.find_keyboards()
                
                # Send results to main thread via queue
                self.device_queue.put(('scan_result', current_keyboards))
                
            except Exception as e:
                print(f"[HOTKEY] Scan thread error: {e}")
            
            # Sleep 2 seconds before next scan
            time.sleep(2.0)
    
    def process_device_queue(self):
        """Process device updates from background thread (runs on main thread)"""
        if not self.running:
            return False
        
        try:
            # Process all queued updates (non-blocking)
            while True:
                try:
                    msg_type, data = self.device_queue.get_nowait()
                    
                    if msg_type == 'scan_result':
                        current_keyboards = data
                        
                        # Check for new devices
                        for path, device in current_keyboards.items():
                            if path not in self.devices:
                                print(f"[HOTKEY] New keyboard detected: {device.name}")
                                self.devices[path] = device
                        
                        # Check for disconnected devices
                        disconnected = []
                        for path in list(self.devices.keys()):
                            if path not in current_keyboards:
                                print(f"[HOTKEY] Keyboard disconnected: {path}")
                                disconnected.append(path)
                        
                        # Remove disconnected devices
                        for path in disconnected:
                            del self.devices[path]
                
                except queue.Empty:
                    break  # No more messages
        
        except Exception as e:
            print(f"[HOTKEY] Queue processing error: {e}")
        
        return True  # Continue timer
    
    def handle_key_press(self, keycode):
        """Handle a key press event"""
        # Track other modifier keys
        if keycode in self.modifier_keys:
            self.other_modifiers.add(keycode)
            print(f"[HOTKEY] Other modifier pressed: {keycode}, active modifiers: {self.other_modifiers}")
            return
        
        # Win key pressed
        if keycode in (ecodes.KEY_LEFTMETA, ecodes.KEY_RIGHTMETA):
            print(f"[HOTKEY] Win key pressed")
            self.win_key_pressed = True
            self.app_manager.win_key_held = True
            # IMPORTANT: Clear contamination when Win is first pressed
            self.non_combo_keys_pressed.clear()
            print(f"[APP] Win key held = TRUE, contamination cleared")
            return

        # Only process keys if Win is held
        if not self.win_key_pressed:
            return

        # Check if this is a combo key
        if keycode in self.combo_keys:
            # CRITICAL CHECK 1: Only execute if NO other modifiers are pressed
            if len(self.other_modifiers) > 0:
                print(f"[HOTKEY] ❌ BLOCKED: Other modifiers detected: {self.other_modifiers}")
                return  # BLOCK the shortcut!
            
            # CRITICAL CHECK 2: Only execute if NO non-combo keys are pressed
            if len(self.non_combo_keys_pressed) > 0:
                print(f"[HOTKEY] ❌ BLOCKED: Non-combo keys detected: {self.non_combo_keys_pressed}")
                return  # BLOCK the shortcut!
            
            # If we reach here, it's a clean Win+TBK press (PURE)
            print(f"[HOTKEY] ✅ Clean PURE combo detected: Win+{keycode}")
            self.app_manager.shortcut_executed = True
            
            # Execute the shortcut
            self._execute_shortcut(keycode)
        else:
            # Non-combo key pressed while Win is held - CONTAMINATE!
            print(f"[HOTKEY] 🚫 Contamination: Non-combo key {keycode} pressed while Win held")
            self.non_combo_keys_pressed.add(keycode)
    
    def _execute_shortcut(self, keycode):
        """Execute the actual shortcut action"""
        # Toggle (Win + `)
        if keycode == ecodes.KEY_GRAVE:
            print(f"[HOTKEY] Toggle shortcut")
            GLib.timeout_add(0, self.app_manager.toggle)

        # Pause (Win + Enter)
        elif keycode == ecodes.KEY_ENTER:
            print(f"[HOTKEY] Pause shortcut")
            GLib.timeout_add(0, self.app_manager.pause)

        # Reset (Win + Backspace)
        elif keycode == ecodes.KEY_BACKSPACE:
            print(f"[HOTKEY] Reset shortcut")
            GLib.timeout_add(0, self.app_manager.reset)

        # Switch mode (Win + Esc)
        elif keycode == ecodes.KEY_ESC:
            print(f"[HOTKEY] Switch mode shortcut")
            GLib.timeout_add(0, self.app_manager.switch_mode)

        # Adjust up (Win + Up) - Timer only
        elif keycode == ecodes.KEY_UP and self.app_manager.mode == "timer":
            # Block if alarm is active
            if hasattr(self.app_manager.timer, 'alarm_gui') and self.app_manager.timer.alarm_gui:
                print(f"[HOTKEY] Alarm active - UP blocked")
                return
            
            if not self.up_key_held:
                self.up_key_held = True
                print(f"[HOTKEY] UP key pressed - starting adjustment")
                GLib.timeout_add(0, self.app_manager.timer.adjust_up_start)

        # Adjust down (Win + Down) - Timer only
        elif keycode == ecodes.KEY_DOWN and self.app_manager.mode == "timer":
            # Block if alarm is active
            if hasattr(self.app_manager.timer, 'alarm_gui') and self.app_manager.timer.alarm_gui:
                print(f"[HOTKEY] Alarm active - DOWN blocked")
                return
            
            if not self.down_key_held:
                self.down_key_held = True
                print(f"[HOTKEY] DOWN key pressed - starting adjustment")
                GLib.timeout_add(0, self.app_manager.timer.adjust_down_start)
    
    def handle_key_release(self, keycode):
        """Handle a key release event"""
        # Track other modifier key releases
        if keycode in self.modifier_keys:
            self.other_modifiers.discard(keycode)
            print(f"[HOTKEY] Other modifier released: {keycode}, active modifiers: {self.other_modifiers}")
            return
        
        # Win key released
        if keycode in (ecodes.KEY_LEFTMETA, ecodes.KEY_RIGHTMETA):
            print(f"[HOTKEY] Win key released")
            self.win_key_pressed = False
            
            # CRITICAL: Clear contamination when Win is released
            print(f"[HOTKEY] Clearing non-combo contamination")
            self.non_combo_keys_pressed.clear()
            
            GLib.timeout_add(0, self.app_manager.on_win_key_release)

            # Also stop any adjustments when Win is released
            if self.up_key_held:
                print(f"[HOTKEY] Stopping UP adjustment (Win released)")
                self.up_key_held = False
                GLib.timeout_add(0, self.app_manager.timer.adjust_up_stop)
            if self.down_key_held:
                print(f"[HOTKEY] Stopping DOWN adjustment (Win released)")
                self.down_key_held = False
                GLib.timeout_add(0, self.app_manager.timer.adjust_down_stop)
            return

        # Remove released key from contamination set
        if keycode in self.non_combo_keys_pressed:
            self.non_combo_keys_pressed.remove(keycode)

        # Up key released
        if keycode == ecodes.KEY_UP:
            if self.up_key_held:
                print(f"[HOTKEY] UP key released")
                self.up_key_held = False
                GLib.timeout_add(0, self.app_manager.timer.adjust_up_stop)

        # Down key released
        elif keycode == ecodes.KEY_DOWN:
            if self.down_key_held:
                print(f"[HOTKEY] DOWN key released")
                self.down_key_held = False
                GLib.timeout_add(0, self.app_manager.timer.adjust_down_stop)
    
    def listen_thread(self):
        """Main listening thread with robust error handling"""
        while self.running:
            if not self.devices:
                # No devices, wait and continue
                time.sleep(0.5)
                continue
            
            try:
                # Use select with timeout on device list
                device_list = list(self.devices.values())
                r, w, x = select.select(device_list, [], [], 0.5)
                
                for dev in r:
                    dev_path = dev.path
                    try:
                        for event in dev.read():
                            if event.type != ecodes.EV_KEY:
                                continue
                            
                            # Key pressed
                            if event.value == 1:
                                self.handle_key_press(event.code)
                            
                            # Key released
                            elif event.value == 0:
                                self.handle_key_release(event.code)
                    
                    except OSError:
                        # Device disconnected - will be handled by scan thread
                        if dev_path in self.devices:
                            print(f"[HOTKEY] Device disconnected: {dev_path}")
                            del self.devices[dev_path]
                    
                    except Exception as e:
                        print(f"[HOTKEY] Unexpected error on {dev_path}: {e}")
            
            except Exception as e:
                # Catch-all for select() errors
                print(f"[HOTKEY] Select error: {e}")
                time.sleep(0.5)
    
    def start(self):
        """Start the hotkey manager"""
        # Initial device scan
        self.devices = self.find_keyboards()
        
        if not self.devices:
            print("[HOTKEY] Warning: No keyboards found initially, but will keep scanning...")
        
        self.running = True
        
        # Start background scanning thread (doesn't block GUI!)
        self.scan_thread = threading.Thread(target=self.scan_thread_worker, daemon=True)
        self.scan_thread.start()
        
        # Start queue processor on main thread (every 500ms is fine, very lightweight)
        GLib.timeout_add(500, self.process_device_queue)
        
        # Start listening thread
        thread = threading.Thread(target=self.listen_thread, daemon=True)
        thread.start()
        
        print("[HOTKEY] Hotkey manager started")
        return True
    
    def stop(self):
        """Stop the hotkey manager"""
        self.running = False
        
        # Wait for scan thread to finish
        if self.scan_thread and self.scan_thread.is_alive():
            self.scan_thread.join(timeout=3.0)
        
        # Close all devices
        for device in self.devices.values():
            try:
                device.close()
            except:
                pass
        
        self.devices.clear()
        print("[HOTKEY] Hotkey manager stopped")