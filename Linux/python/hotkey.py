#!/usr/bin/env python3

from gi.repository import GLib
import evdev
from evdev import ecodes, UInput
import select
import threading
import time
import signal
import sys

try:
    import pyudev
    HAS_PYUDEV = True
except ImportError:
    HAS_PYUDEV = False
    print("[HOTKEY] WARNING: pyudev not installed - hot-swap detection disabled")
    print("[HOTKEY] Install with: pip install pyudev")

class HotkeyManager:
    def __init__(self, app_manager):
        self.app_manager = app_manager
        self.devices = {}
        self.running = False
        self.up_key_held = False
        self.down_key_held = False
        self.win_key_pressed = False
        self.suppression_enabled = False
        self.other_modifiers = set()
        self.modifier_keys = {
            ecodes.KEY_LEFTCTRL, ecodes.KEY_RIGHTCTRL,
            ecodes.KEY_LEFTSHIFT, ecodes.KEY_RIGHTSHIFT,
            ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT
        }
        self.non_combo_keys_pressed = set()
        self.combo_keys = {
            ecodes.KEY_GRAVE,
            ecodes.KEY_ENTER,
            ecodes.KEY_BACKSPACE,
            ecodes.KEY_ESC,
            ecodes.KEY_UP,
            ecodes.KEY_DOWN
        }
        self.suppressed_keys = set()
        self.injected_dummy = False
        self.udev_thread = None
        self.listen_thread = None
        self.devices_lock = threading.Lock()
        
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        
    def _signal_handler(self, signum, frame):
        print("\n[HOTKEY] Caught signal, cleaning up...")
        self.stop()
        sys.exit(0)
        
    def find_keyboards(self):
        keyboards = {}
        try:
            for path in evdev.list_devices():
                try:
                    device = evdev.InputDevice(path)
                    if device.name.startswith('timebomb-virtual-'):
                        continue
                    caps = device.capabilities()
                    if ecodes.EV_KEY in caps:
                        keys = caps[ecodes.EV_KEY]
                        if ecodes.KEY_A in keys and ecodes.KEY_Z in keys:
                            keyboards[path] = device
                            print(f"[HOTKEY] Found keyboard: {device.name} at {path}")
                except Exception:
                    pass
        except Exception as e:
            print(f"[HOTKEY] Error scanning devices: {e}")
        return keyboards
    
    def _setup_device(self, path, real_device):
        with self.devices_lock:
            if self.suppression_enabled:
                try:
                    real_device.grab()
                    print(f"[HOTKEY] ✓ Grabbed: {real_device.name}")
                    safe_name = real_device.name[:50]
                    virtual_device = UInput.from_device(real_device, name=f'timebomb-virtual-{safe_name}')
                    print(f"[HOTKEY] ✓ Created virtual device for suppression")
                    self.devices[path] = (real_device, virtual_device)
                    return
                except Exception as e:
                    print(f"[HOTKEY] ⚠ Could not grab {real_device.name}: {e}")
                    print(f"[HOTKEY]   Falling back to listen-only mode for this device")
            self.devices[path] = real_device
    
    def _cleanup_device(self, path):
        with self.devices_lock:
            if path not in self.devices:
                return
            device_entry = self.devices[path]
            if isinstance(device_entry, tuple):
                real_device, virtual_device = device_entry
                print(f"[HOTKEY] Flushing held keys for {real_device.name}...")
                for mod_key in [ecodes.KEY_LEFTCTRL, ecodes.KEY_RIGHTCTRL,
                               ecodes.KEY_LEFTSHIFT, ecodes.KEY_RIGHTSHIFT,
                               ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT,
                               ecodes.KEY_LEFTMETA, ecodes.KEY_RIGHTMETA]:
                    try:
                        virtual_device.write(ecodes.EV_KEY, mod_key, 0)
                        virtual_device.syn()
                    except:
                        pass
                for tbk in self.combo_keys:
                    try:
                        virtual_device.write(ecodes.EV_KEY, tbk, 0)
                        virtual_device.syn()
                    except:
                        pass
                for keycode in list(self.suppressed_keys):
                    try:
                        virtual_device.write(ecodes.EV_KEY, keycode, 0)
                        virtual_device.syn()
                    except:
                        pass
                try:
                    real_device.ungrab()
                    virtual_device.close()
                    print(f"[HOTKEY] ✓ Cleaned up {real_device.name}")
                except Exception as e:
                    print(f"[HOTKEY] Error during cleanup: {e}")
            else:
                try:
                    device_entry.close()
                    print(f"[HOTKEY] ✓ Closed {device_entry.name}")
                except:
                    pass
            del self.devices[path]
    
    def udev_monitor_worker(self):
        if not HAS_PYUDEV:
            print("[HOTKEY] udev monitoring unavailable - pyudev not installed")
            return
        try:
            context = pyudev.Context()
            monitor = pyudev.Monitor.from_netlink(context)
            monitor.filter_by(subsystem='input')
            print("[HOTKEY] udev monitoring started")
            for device in iter(monitor.poll, None):
                if not self.running:
                    break
                if device.action == 'remove':
                    device_name = device.get('NAME', 'Unknown')
                    devnode = device.device_node
                    print(f"[HOTKEY] ❌ UDEV REMOVE: {device_name}")
                    with self.devices_lock:
                        for path in list(self.devices.keys()):
                            if path == devnode or devnode is None:
                                self._cleanup_device(path)
                elif device.action == 'add':
                    device_name = device.get('NAME', 'Unknown')
                    print(f"[HOTKEY] ✅ UDEV ADD: {device_name}")
                    time.sleep(0.15)
                    current = self.find_keyboards()
                    for path, dev in current.items():
                        if path not in self.devices:
                            self._setup_device(path, dev)
        except Exception as e:
            print(f"[HOTKEY] udev monitor error: {e}")
    
    def handle_key_press(self, keycode):
        if keycode in self.modifier_keys:
            self.other_modifiers.add(keycode)
            return
        if keycode in (ecodes.KEY_LEFTMETA, ecodes.KEY_RIGHTMETA):
            print(f"[HOTKEY] Win key pressed")
            self.win_key_pressed = True
            self.app_manager.win_key_held = True
            self.non_combo_keys_pressed.clear()
            self.injected_dummy = False
            print(f"[APP] Win key held = TRUE")
            return
        if not self.win_key_pressed:
            return
        if keycode in self.combo_keys:
            if len(self.other_modifiers) > 0:
                print(f"[HOTKEY] ❌ BLOCKED: Other modifiers detected")
                return
            if len(self.non_combo_keys_pressed) > 0:
                print(f"[HOTKEY] ❌ BLOCKED: Non-combo keys detected")
                return
            print(f"[HOTKEY] ✅ PURE Win+TBK detected")
            self.app_manager.shortcut_executed = True
            self._execute_shortcut(keycode)
        else:
            print(f"[HOTKEY] 🚫 Contamination: NTBK pressed")
            self.non_combo_keys_pressed.add(keycode)
    
    def _execute_shortcut(self, keycode):
        if keycode == ecodes.KEY_GRAVE:
            print(f"[HOTKEY] → Toggle")
            GLib.timeout_add(0, self.app_manager.toggle)
        elif keycode == ecodes.KEY_ENTER:
            print(f"[HOTKEY] → Pause")
            GLib.timeout_add(0, self.app_manager.pause)
        elif keycode == ecodes.KEY_BACKSPACE:
            print(f"[HOTKEY] → Reset")
            GLib.timeout_add(0, self.app_manager.reset)
        elif keycode == ecodes.KEY_ESC:
            print(f"[HOTKEY] → Switch mode")
            GLib.timeout_add(0, self.app_manager.switch_mode)
        elif keycode == ecodes.KEY_UP and self.app_manager.mode == "timer":
            if hasattr(self.app_manager.timer, 'alarm_gui') and self.app_manager.timer.alarm_gui:
                return
            if not self.up_key_held:
                self.up_key_held = True
                GLib.timeout_add(0, self.app_manager.timer.adjust_up_start)
        elif keycode == ecodes.KEY_DOWN and self.app_manager.mode == "timer":
            if hasattr(self.app_manager.timer, 'alarm_gui') and self.app_manager.timer.alarm_gui:
                return
            if not self.down_key_held:
                self.down_key_held = True
                GLib.timeout_add(0, self.app_manager.timer.adjust_down_start)
    
    def handle_key_release(self, keycode):
        if keycode in self.modifier_keys:
            self.other_modifiers.discard(keycode)
            return
        if keycode in (ecodes.KEY_LEFTMETA, ecodes.KEY_RIGHTMETA):
            print(f"[HOTKEY] Win key released")
            self.win_key_pressed = False
            self.non_combo_keys_pressed.clear()
            self.injected_dummy = False
            GLib.timeout_add(0, self.app_manager.on_win_key_release)
            if self.up_key_held:
                self.up_key_held = False
                GLib.timeout_add(0, self.app_manager.timer.adjust_up_stop)
            if self.down_key_held:
                self.down_key_held = False
                GLib.timeout_add(0, self.app_manager.timer.adjust_down_stop)
            return
        if keycode in self.non_combo_keys_pressed:
            self.non_combo_keys_pressed.remove(keycode)
        if keycode == ecodes.KEY_UP:
            if self.up_key_held:
                self.up_key_held = False
                GLib.timeout_add(0, self.app_manager.timer.adjust_up_stop)
        elif keycode == ecodes.KEY_DOWN:
            if self.down_key_held:
                self.down_key_held = False
                GLib.timeout_add(0, self.app_manager.timer.adjust_down_stop)
    
    def should_suppress(self, keycode):
        if keycode in self.combo_keys and self.win_key_pressed and not self.other_modifiers:
            return True
        return False
    
    def listen_worker(self):
        while self.running:
            with self.devices_lock:
                if not self.devices:
                    time.sleep(0.1)
                    continue
                device_list = []
                path_map = {}
                for path, entry in self.devices.items():
                    if isinstance(entry, tuple):
                        real_dev, virt_dev = entry
                        device_list.append(real_dev)
                        path_map[real_dev.path] = (path, virt_dev)
                    else:
                        device_list.append(entry)
                        path_map[entry.path] = (path, None)
            if not device_list:
                time.sleep(0.1)
                continue
            try:
                r, w, x = select.select(device_list, [], [], 0.5)
                for real_dev in r:
                    path, virtual_dev = path_map.get(real_dev.path, (None, None))
                    if path is None:
                        continue
                    try:
                        for event in real_dev.read():
                            suppress = False
                            if event.type == ecodes.EV_KEY:
                                if event.value == 1:
                                    if virtual_dev and self.should_suppress(event.code):
                                        print(f"[SPRS] 🚫 Suppressing {event.code} from OS")
                                        suppress = True
                                        self.suppressed_keys.add(event.code)
                                        if not self.injected_dummy:
                                            print(f"[SPRS] 💉 Dummy Shift injection")
                                            virtual_dev.write(ecodes.EV_KEY, ecodes.KEY_LEFTSHIFT, 1)
                                            virtual_dev.syn()
                                            virtual_dev.write(ecodes.EV_KEY, ecodes.KEY_LEFTSHIFT, 0)
                                            virtual_dev.syn()
                                            self.injected_dummy = True
                                    self.handle_key_press(event.code)
                                elif event.value == 0:
                                    if event.code in self.suppressed_keys:
                                        print(f"[SPRS] 🚫 Suppressing {event.code} release")
                                        suppress = True
                                        self.suppressed_keys.discard(event.code)
                                    self.handle_key_release(event.code)
                            if not suppress and virtual_dev:
                                virtual_dev.write_event(event)
                                virtual_dev.syn()
                    except OSError:
                        print(f"[HOTKEY] Device read error: {path}")
                    except Exception as e:
                        print(f"[HOTKEY] Error on {path}: {e}")
            except Exception as e:
                print(f"[HOTKEY] Select error: {e}")
                time.sleep(0.5)
    
    def start(self):
        print("[HOTKEY] Starting hotkey manager...")
        print("[HOTKEY] Attempting to enable suppression...")
        self.suppression_enabled = True
        keyboards = self.find_keyboards()
        if not keyboards:
            print("[HOTKEY] ⚠ No keyboards found initially")
        for path, device in keyboards.items():
            self._setup_device(path, device)
        has_suppression = any(isinstance(entry, tuple) for entry in self.devices.values())
        if has_suppression:
            print("[HOTKEY] ✓ Suppression ENABLED for some devices!")
        else:
            print("[HOTKEY] ⚠ Suppression DISABLED (no devices grabbed)")
            print("[HOTKEY]   Shortcuts will work but Win menu may appear")
            print("[HOTKEY]   Make sure you're in 'input' group: sudo usermod -a -G input $USER")
        self.running = True
        if HAS_PYUDEV:
            self.udev_thread = threading.Thread(target=self.udev_monitor_worker, daemon=True)
            self.udev_thread.start()
        else:
            print("[HOTKEY] ⚠ Running without hot-swap detection")
        self.listen_thread = threading.Thread(target=self.listen_worker, daemon=True)
        self.listen_thread.start()
        print("[HOTKEY] ✓ Started!")
        return True
    
    def stop(self):
        if not self.running:
            return
        print("[HOTKEY] Stopping and flushing all keys...")
        self.running = False
        if self.udev_thread and self.udev_thread.is_alive():
            self.udev_thread.join(timeout=2.0)
        if self.listen_thread and self.listen_thread.is_alive():
            self.listen_thread.join(timeout=2.0)
        with self.devices_lock:
            for path in list(self.devices.keys()):
                self._cleanup_device(path)
            self.devices.clear()
        print("[HOTKEY] Stopped")