import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GLib
import subprocess
import os
import logging


# Try to import GtkLayerShell for Wayland overlay support
try:
    gi.require_version('GtkLayerShell', '0.1')
    from gi.repository import GtkLayerShell
    HAS_LAYER_SHELL = True
except (ValueError, ImportError):
    HAS_LAYER_SHELL = False
    print("[GUI] GtkLayerShell not available - using fallback method")

# ==================== DYNAMIC SCALING ====================
class ScreenScaler:
    """Calculate DPI-aware scaling based on screen resolution"""
    # Reference: 1920x1080 (full HD) - these are the base sizes
    REFERENCE_WIDTH = 1920
    REFERENCE_HEIGHT = 1080
    
    # Base UI sizes (pixels) designed for 1920x1080
    BASE_WINDOW_WIDTH = 180
    BASE_WINDOW_HEIGHT = 85
    BASE_MAIN_FONT_SIZE = 40
    BASE_SUB_FONT_SIZE = 18
    BASE_PREFIX_FONT_SIZE = 18
    BASE_MARGIN = 6
    BASE_PADDING = 8
    
    def __init__(self):
        """Initialize scaler with current screen dimensions"""
        display = Gdk.Display.get_default()
        screen = display.get_default_screen() if display else Gdk.Screen.get_default()
        
        self.screen_width = screen.get_width()
        self.screen_height = screen.get_height()
        
        # Calculate scale factor based on shorter dimension (handles portrait/landscape)
        # Use the ratio that makes most sense for scaling UI
        width_ratio = self.screen_width / self.REFERENCE_WIDTH
        height_ratio = self.screen_height / self.REFERENCE_HEIGHT
        
        # Use geometric mean for more balanced scaling across different aspect ratios
        import math
        self.scale_factor = math.sqrt(width_ratio * height_ratio)
        
        # Clamp between 0.5x and 2.0x to avoid extreme scaling
        self.scale_factor = max(0.5, min(2.0, self.scale_factor))
        
        print(f"[GUI] Screen: {self.screen_width}x{self.screen_height}")
        print(f"[GUI] Scale factor: {self.scale_factor:.2f}x")
    
    def scale_size(self, base_size):
        """Scale a size value"""
        return int(base_size * self.scale_factor)
    
    def scale_font(self, base_font_size):
        """Scale font size"""
        return int(base_font_size * self.scale_factor)
    
    def get_window_size(self):
        """Get scaled window dimensions"""
        return (
            self.scale_size(self.BASE_WINDOW_WIDTH),
            self.scale_size(self.BASE_WINDOW_HEIGHT)
        )
    
    def get_font_sizes(self):
        """Get all scaled font sizes"""
        return {
            'main': self.scale_font(self.BASE_MAIN_FONT_SIZE),
            'sub': self.scale_font(self.BASE_SUB_FONT_SIZE),
            'prefix': self.scale_font(self.BASE_PREFIX_FONT_SIZE),
        }
    
    def get_margins(self):
        """Get scaled margins"""
        return {
            'margin': self.scale_size(self.BASE_MARGIN),
            'padding': self.scale_size(self.BASE_PADDING),
        }

# ==================== GUI ====================
class AppGUI(Gtk.Window):
    def __init__(self):
        super().__init__()
        
        # Initialize logger
        self.logger = logging.getLogger(__name__)
        self.logger.info("Initializing GUI...")
        
        # Initialize scaler
        self.scaler = ScreenScaler()
        
        # Detect if we're on Wayland
        display = Gdk.Display.get_default()
        self.is_wayland = display and type(display).__name__ == 'GdkWaylandDisplay'
        
        self.logger.info(f"Display type: {'Wayland' if self.is_wayland else 'X11'}")
        self.logger.info(f"Layer Shell available: {HAS_LAYER_SHELL}")
        
        # Window behavior - Basic setup first
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_accept_focus(False)
        
        # Apply Layer Shell if on Wayland and available
        if self.is_wayland and HAS_LAYER_SHELL:
            self._setup_layer_shell()
        else:
            self._setup_fallback()
        
        # Transparency
        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual:
            self.set_visual(visual)
        self.set_app_paintable(True)

        # Size - now scaled dynamically
        width, height = self.scaler.get_window_size()
        self.set_default_size(width, height)

        # Frame holder
        frame = Gtk.EventBox()
        frame.set_name("box")
        self.add(frame)

        # Layout
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        margins = self.scaler.get_margins()
        vbox.set_margin_top(margins['margin'])
        vbox.set_margin_bottom(margins['margin'])
        vbox.set_margin_start(margins['padding'])
        vbox.set_margin_end(margins['padding'])
        frame.add(vbox)

        # Main time label
        self.main_label = Gtk.Label(label="00:00")
        self.main_label.set_name("main_time")
        self.main_label.set_halign(Gtk.Align.CENTER)
        vbox.pack_start(self.main_label, False, False, 0)

        # Bottom row
        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        hbox.set_halign(Gtk.Align.CENTER)

        self.prefix_label = Gtk.Label(label="Started:")
        self.prefix_label.set_name("prefix")

        self.sub_time_label = Gtk.Label(label="--:--:--")
        self.sub_time_label.set_name("end_time")

        hbox.pack_start(self.prefix_label, False, False, 0)
        hbox.pack_start(self.sub_time_label, False, False, 0)

        vbox.pack_start(hbox, False, False, 0)

        self.apply_css()
        self.enable_drag()
        
        self.logger.info("GUI initialized successfully")

    def _setup_layer_shell(self):
        """Setup Layer Shell for Wayland - puts window ABOVE fullscreen apps"""
        self.logger.info("Configuring Layer Shell (Wayland overlay mode)")
        
        # Initialize layer shell for this window
        GtkLayerShell.init_for_window(self)
        
        # Set to OVERLAY layer - this is ABOVE fullscreen apps!
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        
        # Don't anchor to any edge (free-floating)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, False)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, False)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, False)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, False)
        
        # Set namespace
        GtkLayerShell.set_namespace(self, "timebomb")
        
        # Disable exclusive zone (don't push other windows)
        GtkLayerShell.auto_exclusive_zone_enable(self)
        
        self.logger.info("Layer Shell configured - window will be above fullscreen apps")
    
    def _setup_fallback(self):
        """Fallback method for X11 or when Layer Shell unavailable"""
        self.logger.info("Using fallback window configuration (X11 mode)")
        
        # Use DOCK type hint - works reasonably on X11
        self.set_type_hint(Gdk.WindowTypeHint.DOCK)
        self.set_keep_above(True)
        
        # Try to force it to stay on top
        self.connect("realize", self._on_realize_fallback)
    
    def _on_realize_fallback(self, widget):
        """Additional tweaks after window is realized (X11 only)"""
        window = self.get_window()
        if window:
            window.set_override_redirect(True)
            window.raise_()

    def get_screen_bounds(self):
        """Get the usable screen dimensions"""
        display = Gdk.Display.get_default()
        monitor = display.get_primary_monitor()
        if not monitor:
            # Fallback: get monitor at pointer position
            screen = Gdk.Screen.get_default()
            display = screen.get_display()
            seat = display.get_default_seat()
            pointer = seat.get_pointer()
            _, x, y = pointer.get_position()
            monitor = display.get_monitor_at_point(x, y)
        
        geometry = monitor.get_geometry()
        return geometry.x, geometry.y, geometry.width, geometry.height

    def constrain_to_screen(self, x, y):
        """Constrain window position to stay within screen bounds"""
        # Get screen dimensions
        screen_x, screen_y, screen_width, screen_height = self.get_screen_bounds()
        
        # Get window size
        win_width, win_height = self.get_size()
        
        # Constrain X position
        if x < screen_x:
            x = screen_x
        elif x + win_width > screen_x + screen_width:
            x = screen_x + screen_width - win_width
        
        # Constrain Y position
        if y < screen_y:
            y = screen_y
        elif y + win_height > screen_y + screen_height:
            y = screen_y + screen_height - win_height
        
        return int(x), int(y)

    def set_time(self, text):
        self.main_label.set_text(text)

    def set_sub_time(self, text):
        self.sub_time_label.set_text(text)
    
    def set_prefix(self, text):
        self.prefix_label.set_text(text)

    def apply_css(self):
        fonts = self.scaler.get_font_sizes()
        
        css = f"""
        window {{ background: transparent; }}

        #box {{
            background-color: rgba(64,64,69,0.85);
            border: 1px solid rgba(10,10,12,0.95);
            border-radius: 6px;
        }}

        label {{
            background: transparent;
            font-family: Arial;
            font-size: {fonts['prefix']}px;
            font-weight: bold;
            color: #A0FFA0;
        }}

        #main_time {{
            font-family: "DS-Digital", monospace;
            font-size: {fonts['main']}px;
            color: #23FF23;
        }}

        #main_time_red {{
            font-family: "DS-Digital", monospace;
            font-size: {fonts['main']}px;
            color: #FF2323;
        }}

        #end_time {{
            font-family: Arial;
            font-size: {fonts['sub']}px;
            font-weight: bold;
            color: #A0FFA0;
        }}

        #prefix {{
            font-size: {fonts['prefix']}px;
            color: #A0FFA0;
        }}
        """.encode()

        provider = Gtk.CssProvider()
        provider.load_from_data(css)

        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def enable_drag(self):
        self.dragging = False
        self.add_events(
            Gdk.EventMask.BUTTON_PRESS_MASK |
            Gdk.EventMask.POINTER_MOTION_MASK |
            Gdk.EventMask.BUTTON_RELEASE_MASK
        )
        self.connect("button-press-event", self.on_press)
        self.connect("motion-notify-event", self.on_drag)
        self.connect("button-release-event", self.on_release)
    
    def check_and_raise(self):
        """Periodically check if we need to raise the window"""
        if self.get_visible():
            # Only needed for X11 fallback mode
            if not self.is_wayland:
                self.present()
                window = self.get_window()
                if window:
                    window.raise_()
                    window.focus(Gdk.CURRENT_TIME)
        return True
    
    def start_raise_timer(self):
        """Start periodic window raising when visible"""
        # Only needed for X11 mode - Layer Shell handles this automatically
        if not (self.is_wayland and HAS_LAYER_SHELL):
            GLib.timeout_add(500, self.check_and_raise)

    def on_press(self, widget, event):
        if event.button == 1:
            self.dragging = True
            win_x, win_y = self.get_position()
            self.offset_x = event.x_root - win_x
            self.offset_y = event.y_root - win_y
        return True

    def on_drag(self, widget, event):
        if self.dragging:
            # Calculate new position
            new_x = int(event.x_root - self.offset_x)
            new_y = int(event.y_root - self.offset_y)
            
            # Constrain to screen bounds
            constrained_x, constrained_y = self.constrain_to_screen(new_x, new_y)
            
            # Move window
            self.move(constrained_x, constrained_y)
        return True

    def on_release(self, widget, event):
        if self.dragging:
            self.dragging = False
            
            # Final position constraint check
            win_x, win_y = self.get_position()
            constrained_x, constrained_y = self.constrain_to_screen(win_x, win_y)
            
            # Move to constrained position if needed
            if win_x != constrained_x or win_y != constrained_y:
                self.move(constrained_x, constrained_y)
            
            if hasattr(self, 'save_callback'):
                self.save_callback()
        return True


# ==================== ALARM GUI ====================
class AlarmGUI(Gtk.Window):
    def __init__(self, on_dismiss=None, on_reset=None, message="Beep, Beep turn it off."):
        super().__init__()
        
        # Initialize logger
        self.logger = logging.getLogger(__name__)
        self.logger.info("Initializing Alarm GUI...")
        
        self.on_dismiss = on_dismiss or (lambda: None)
        self.on_reset = on_reset or (lambda: None)
        
        # Initialize scaler
        scaler = ScreenScaler()
        
        # Detect Wayland
        display = Gdk.Display.get_default()
        is_wayland = display and type(display).__name__ == 'GdkWaylandDisplay'
        
        # Window settings - use scaled dimensions
        alarm_width = scaler.scale_size(440)
        alarm_height = scaler.scale_size(90)
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_default_size(alarm_width, alarm_height)
        self.set_resizable(False)
        
        # Apply Layer Shell if on Wayland
        if is_wayland and HAS_LAYER_SHELL:
            GtkLayerShell.init_for_window(self)
            GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
            GtkLayerShell.set_namespace(self, "timebomb-alarm")
            # Center the alarm on screen
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, False)
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, False)
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, False)
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, False)
            self.logger.info("Alarm using Layer Shell - will appear above fullscreen")
        else:
            self.set_type_hint(Gdk.WindowTypeHint.DOCK)
            self.set_keep_above(True)
        
        # Background
        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual:
            self.set_visual(visual)
        self.override_background_color(Gtk.StateFlags.NORMAL, Gdk.RGBA(0.250, 0.250, 0.270, 1.0))
        
        # Layout
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=15)
        vbox.set_border_width(20)          
        self.add(vbox)

        # Message
        self.label = Gtk.Label()
        self.label.set_name("alarm_text")
        self.label.set_justify(Gtk.Justification.CENTER)
        vbox.pack_start(self.label, True, True, 10)  
        self.set_message(message)

        # Buttons container
        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        hbox.set_halign(Gtk.Align.CENTER)
        
        # Done button (first)
        self.done_btn = Gtk.Button(label="Done")
        self.done_btn.set_size_request(120, 42)
        self.done_btn.set_can_focus(True)
        self.done_btn.get_style_context().add_class("alarm_button")
        self.done_btn.connect("clicked", lambda _: self.dismiss())
        hbox.pack_start(self.done_btn, False, False, 0)
        
        # Reset button (second)
        self.reset_btn = Gtk.Button(label="Reset")
        self.reset_btn.set_size_request(120, 42)
        self.reset_btn.set_can_focus(True)
        self.reset_btn.get_style_context().add_class("alarm_button")
        self.reset_btn.connect("clicked", lambda _: self.reset_and_dismiss())
        hbox.pack_start(self.reset_btn, False, False, 0)

        vbox.pack_start(hbox, False, False, 0)

        self.apply_css()
        
        # Connect keyboard handler to block spacebar
        self.connect("key-press-event", self.on_key_press)
        
        self.logger.info("Alarm GUI initialized")

    def set_message(self, text):
        scaler = ScreenScaler()
        fonts = scaler.get_font_sizes()
        escaped = GLib.markup_escape_text(text)
        self.label.set_markup(
            f'<span font="{fonts["main"]}" foreground="#A0FFA0" font_family="DS-Digital">{escaped}</span>'
        )
    
    def on_key_press(self, widget, event):
        """Block spacebar from activating buttons"""
        if event.keyval == Gdk.KEY_space:
            return True  # Block spacebar
        return False  # Allow other keys

    def apply_css(self):
        scaler = ScreenScaler()
        fonts = scaler.get_font_sizes()
        button_font = scaler.scale_font(11)
        
        css = f"""
        window {{ background: #404045; }}
        #alarm_text {{ 
            font-family: "DS-Digital"; 
            color: #A0FFA0; 
        }}
        .alarm_button {{
            font-family: "DS-Digital";
            font-size: {button_font}px;
            background: #404045;
            color: #A0FFA0;
            border: 1px solid #23FF23;
            font-weight: bold;
        }}
        .alarm_button:hover  {{ background: #505055; }}
        .alarm_button:active {{ background: #A0FFA0; }}
        .alarm_button:focus {{
            background: #505055;
            border: 2px solid #23FF23;
            box-shadow: 0 0 2px #23FF23;
        }}
        """.encode()
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def play_alarm(self):
        try:
            # Get the python directory parent (timebomb root)
            base_dir = os.path.dirname(os.path.dirname(__file__))
            path = os.path.join(base_dir, "assets", "sounds", "alarm.wav")
            if os.path.exists(path):
                subprocess.Popen(["paplay", path],
                               stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
            else:
                self.logger.warning(f"Alarm sound file not found: {path}")
        except Exception as e:
            self.logger.error(f"Failed to play alarm sound: {e}", exc_info=True)

    def start_alarm_loop(self):
        self.logger.info("Starting alarm loop")
        self.play_alarm()
        GLib.timeout_add(1000, self._loop)

    def _loop(self):
        if self.get_visible():
            self.play_alarm()
            return True
        return False

    def stop_alarm(self):
        try:
            subprocess.call(["pkill", "-f", "paplay.*alarm.wav"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.logger.info("Alarm stopped")
        except Exception as e:
            self.logger.error(f"Failed to stop alarm: {e}", exc_info=True)

    def reset_and_dismiss(self):
        self.logger.info("Alarm reset and dismissed")
        self.stop_alarm()
        self.on_reset()
        self.destroy()

    def dismiss(self):
        self.logger.info("Alarm dismissed")
        self.stop_alarm()
        self.on_dismiss()
        self.destroy()