#!/home/john/src/talkie/bin/python3

import logging
import numpy as np
import tkinter as tk
from tkinter import scrolledtext, ttk

logger = logging.getLogger(__name__)

class TalkieGUI:
    """Manages the Tkinter GUI interface for Talkie"""
    
    def __init__(self, master, audio_manager, config_manager, text_processor, app=None):
        self.master = master
        self.audio_manager = audio_manager
        self.config_manager = config_manager
        self.text_processor = text_processor
        self.app = app  # Reference to TalkieApplication for Vosk parameter updates
        
        # Set up callbacks
        self.audio_manager.set_transcription_change_callback(self.update_ui)
        
        self._setup_ui()
        self._setup_device_selection()
        self._start_energy_display_updates()
        
        # Initialize bubble feature state
        self._initialize_bubble_feature()
        
        # Initial UI state will be set by the file monitor callback
    
    def _setup_ui(self):
        """Initialize the main UI components"""
        self.master.title("Talkie")

        # Set window icon (window class is set at Tk() creation in talkie.py)
        try:
            import os
            icon_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "icon.png")
            if os.path.exists(icon_path):
                self.master.iconphoto(True, tk.PhotoImage(file=icon_path))
                logger.debug(f"Set window icon: {icon_path}")
        except Exception as e:
            logger.warning(f"Could not set window icon: {e}")

        # Set fixed window size to prevent resizing when switching views
        self._restore_window_position()
        self.master.minsize(800, 400)
        
        # Bind Alt+Q to quit_app function
        self.master.bind("<Alt-q>", lambda event: self.quit_app())
        
        # Save window position when window is moved or closed
        self.master.protocol("WM_DELETE_WINDOW", self._on_window_close)
        self.master.bind("<Configure>", self._on_window_configure)
        
        
        # Button row frame
        button_frame = tk.Frame(self.master)
        button_frame.pack(fill=tk.X, pady=10)
        
        # Main transcription toggle button (flush left)
        self.button = tk.Button(button_frame, text="Start Transcription", command=self.toggle_transcription,
                               activebackground="indianred")  # Hover effect for stopped state
        self.button.pack(side=tk.LEFT, pady=0)
        
        # View switching buttons (left-center)
        self.controls_view_button = tk.Button(button_frame, text="Controls", 
                                            command=self.show_controls_view)
        self.controls_view_button.pack(side=tk.LEFT, padx=5, pady=0)
        
        self.text_view_button = tk.Button(button_frame, text="Text", 
                                         command=self.show_text_view,
                                         relief="sunken")  # Start with text view active
        self.text_view_button.pack(side=tk.LEFT, pady=0)
        
        # Audio energy display (center-left) - styled like a button, same row
        self.energy_label = tk.Label(button_frame, text="Audio: 0", 
                                    relief="raised", bd=2, 
                                    padx=10, pady=5, 
                                    font=("Arial", 10))
        self.energy_label.pack(side=tk.LEFT, expand=True, padx=(10, 5), pady=0)
        
        # Confidence display (center-right) - styled like a button, same row
        self.confidence_label = tk.Label(button_frame, text="Conf: --", 
                                       relief="raised", bd=2, 
                                       padx=10, pady=5, 
                                       font=("Arial", 10))
        self.confidence_label.pack(side=tk.LEFT, expand=True, padx=(5, 10), pady=0)
        
        # Quit button (flush right)
        self.quit_button = tk.Button(button_frame, text="Quit", command=self.quit_app)
        self.quit_button.pack(side=tk.RIGHT, pady=0)
        
        # Create the two switchable panes
        self._setup_switchable_panes()
    
    def _setup_device_selection(self):
        """Set current device from config"""
        try:
            config = self.config_manager.load_config()
            current_device = config.get("audio_device", "pulse")
            
            # Find matching device in the list
            for display_name, device_id, device_name in self.available_devices:
                # Check if the config device matches by name or ID
                if (current_device.lower() in device_name.lower() or 
                    (current_device.isdigit() and int(current_device) == device_id)):
                    self.device_var.set(display_name)
                    logger.debug(f"Set UI device to: {display_name}")
                    break
            else:
                # Fallback to first device if no match found
                if self.available_devices:
                    self.device_var.set(self.available_devices[0][0])
                    logger.warning(f"Device '{current_device}' not found, using first available")
        except Exception as e:
            logger.error(f"Error setting current device from config: {e}")
    
    def _setup_switchable_panes(self):
        """Setup the two switchable panes for controls and text"""
        # Create container for switchable content
        self.content_frame = tk.Frame(self.master)
        self.content_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=5)
        
        # Controls pane with scrollbar
        self.controls_pane = tk.Frame(self.content_frame)
        self._setup_scrollable_controls_pane()
        
        # Text pane  
        self.text_pane = tk.Frame(self.content_frame)
        self._setup_text_areas_in_pane()
        
        # Start with text view
        self.current_view = "text"
        self.show_text_view()
    
    def _setup_scrollable_controls_pane(self):
        """Setup scrollable controls pane with canvas and scrollbar"""
        # Create canvas and scrollbar for scrolling
        self.controls_canvas = tk.Canvas(self.controls_pane)
        self.controls_scrollbar = tk.Scrollbar(self.controls_pane, orient="vertical", command=self.controls_canvas.yview)
        
        # Create scrollable frame inside canvas
        self.scrollable_controls_frame = tk.Frame(self.controls_canvas)
        
        # Configure canvas
        self.controls_canvas.configure(yscrollcommand=self.controls_scrollbar.set)
        self.controls_canvas.create_window((0, 0), window=self.scrollable_controls_frame, anchor="nw")
        
        # Pack canvas and scrollbar
        self.controls_canvas.pack(side="left", fill="both", expand=True)
        self.controls_scrollbar.pack(side="right", fill="y")
        
        # Bind mousewheel to canvas (Windows and Linux)
        def _on_mousewheel(event):
            self.controls_canvas.yview_scroll(int(-1*(event.delta/120)), "units")
            
        def _on_mousewheel_linux(event):
            self.controls_canvas.yview_scroll(-1, "units")
            
        def _on_mousewheel_linux_up(event):
            self.controls_canvas.yview_scroll(1, "units")
        
        def _on_configure(event):
            self.controls_canvas.configure(scrollregion=self.controls_canvas.bbox("all"))
        
        self.scrollable_controls_frame.bind("<Configure>", _on_configure)
        self.controls_canvas.bind("<MouseWheel>", _on_mousewheel)  # Windows
        self.controls_canvas.bind("<Button-4>", _on_mousewheel_linux_up)  # Linux scroll up
        self.controls_canvas.bind("<Button-5>", _on_mousewheel_linux)     # Linux scroll down
        
        # Setup controls in the scrollable frame
        self._setup_controls_column_in_scrollable_frame()
    
    def _setup_controls_column_in_scrollable_frame(self):
        """Setup controls column within the scrollable frame"""
        # Main controls frame within the scrollable frame
        controls_container = tk.Frame(self.scrollable_controls_frame)
        controls_container.pack(pady=10, padx=20, fill=tk.X)
        
        # Setup simplified control rows
        self._setup_device_row(controls_container)
        self._setup_energy_threshold_row(controls_container)
        self._setup_lookback_duration_row(controls_container)
        self._setup_silence_duration_row(controls_container)
        self._setup_vosk_parameters_row(controls_container)
        self._setup_bubble_row(controls_container)
    
    def _setup_device_row(self, parent):
        """Setup audio device selection row"""
        device_frame = tk.Frame(parent)
        device_frame.pack(fill=tk.X, pady=2)
        
        tk.Label(device_frame, text="Audio Device:", width=20, anchor="w").pack(side=tk.LEFT)
        
        # Get available devices
        self.available_devices = self.audio_manager.get_input_devices_for_ui()
        device_names = [device[0] for device in self.available_devices]
        
        device_control_frame = tk.Frame(device_frame)
        device_control_frame.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        
        self.device_var = tk.StringVar()
        self.device_combo = ttk.Combobox(device_control_frame, 
                                        textvariable=self.device_var,
                                        values=device_names,
                                        state="readonly")
        self.device_combo.pack(side=tk.LEFT, fill=tk.X, expand=True)
        self.device_combo.bind("<<ComboboxSelected>>", self.on_device_change)
        self._setup_device_selection()
    
    def _setup_threshold_row(self, parent):
        """Setup voice threshold row"""
        threshold_frame = tk.Frame(parent)
        threshold_frame.pack(fill=tk.X, pady=2)
        
        tk.Label(threshold_frame, text="Voice Threshold:", width=20, anchor="w").pack(side=tk.LEFT)
        
        threshold_control_frame = tk.Frame(threshold_frame)
        threshold_control_frame.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        
        self.threshold_var = tk.DoubleVar(value=self.audio_manager.voice_threshold)
        self.threshold_scale = tk.Scale(threshold_control_frame, from_=10, to=300, 
                                       resolution=5, orient=tk.HORIZONTAL, 
                                       variable=self.threshold_var,
                                       command=self.update_threshold)
        self.threshold_scale.pack(fill=tk.X, expand=True)
    
    def _setup_silence_row(self, parent):
        """Setup silence trailing duration row"""
        silence_frame = tk.Frame(parent)
        silence_frame.pack(fill=tk.X, pady=2)
        
        tk.Label(silence_frame, text="Silence Trailing (s):", width=20, anchor="w").pack(side=tk.LEFT)
        
        silence_control_frame = tk.Frame(silence_frame)
        silence_control_frame.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        
        self.silence_var = tk.DoubleVar(value=self.audio_manager.silence_trailing_duration)
        self.silence_scale = tk.Scale(silence_control_frame, from_=0.1, to=2.0, 
                                     resolution=0.1, orient=tk.HORIZONTAL, 
                                     variable=self.silence_var)
        self.silence_scale.pack(fill=tk.X, expand=True)
    
    
    def _setup_lookback_row(self, parent):
        """Setup lookback frames row"""
        lookback_frame = tk.Frame(parent)
        lookback_frame.pack(fill=tk.X, pady=2)
        
        tk.Label(lookback_frame, text="Lookback Frames (ms):", width=20, anchor="w").pack(side=tk.LEFT)
        
        lookback_control_frame = tk.Frame(lookback_frame)
        lookback_control_frame.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        
        # Convert frames to milliseconds for display
        initial_ms = self.audio_manager.lookback_frames * 100
        self.lookback_var = tk.IntVar(value=initial_ms)
        self.lookback_scale = tk.Scale(lookback_control_frame, from_=100, to=2000, 
                                      resolution=100, orient=tk.HORIZONTAL, 
                                      variable=self.lookback_var)
        self.lookback_scale.pack(fill=tk.X, expand=True)
    
    def _setup_raw_mode_row(self, parent):
        """Setup raw mode checkbox row"""
        raw_frame = tk.Frame(parent)
        raw_frame.pack(fill=tk.X, pady=2)
        
        tk.Label(raw_frame, text="Raw Mode:", width=20, anchor="w").pack(side=tk.LEFT)
        
        raw_control_frame = tk.Frame(raw_frame)
        raw_control_frame.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        
        self.raw_mode_var = tk.BooleanVar(value=self.audio_manager.raw_mode)
        self.raw_mode_checkbox = tk.Checkbutton(raw_control_frame, text="Bypass VAD (feed all audio to engine)", 
                                               variable=self.raw_mode_var,
                                               command=self.update_raw_mode)
        self.raw_mode_checkbox.pack(side=tk.LEFT)
    
    def _setup_energy_threshold_row(self, parent):
        """Setup energy threshold row"""
        threshold_frame = tk.Frame(parent)
        threshold_frame.pack(fill=tk.X, pady=2)
        
        tk.Label(threshold_frame, text="Energy Threshold:", width=20, anchor="w").pack(side=tk.LEFT)
        
        threshold_control_frame = tk.Frame(threshold_frame)
        threshold_control_frame.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        
        self.energy_threshold_var = tk.DoubleVar(value=self.audio_manager.energy_threshold)
        self.energy_threshold_scale = tk.Scale(threshold_control_frame, from_=10.0, to=200.0, 
                                             resolution=5.0, orient=tk.HORIZONTAL, 
                                             variable=self.energy_threshold_var,
                                             command=self.update_energy_threshold)
        self.energy_threshold_scale.pack(fill=tk.X, expand=True)

    def _setup_lookback_duration_row(self, parent):
        """Setup lookback duration row"""
        lookback_frame = tk.Frame(parent)
        lookback_frame.pack(fill=tk.X, pady=2)

        tk.Label(lookback_frame, text="Lookback Duration (s):", width=20, anchor="w").pack(side=tk.LEFT)

        lookback_control_frame = tk.Frame(lookback_frame)
        lookback_control_frame.pack(side=tk.RIGHT, fill=tk.X, expand=True)

        self.lookback_duration_var = tk.DoubleVar(value=self.audio_manager.lookback_duration)
        self.lookback_duration_scale = tk.Scale(lookback_control_frame, from_=0.5, to=3.0,
                                              resolution=0.1, orient=tk.HORIZONTAL,
                                              variable=self.lookback_duration_var,
                                              command=self.update_lookback_duration)
        self.lookback_duration_scale.pack(fill=tk.X, expand=True)

    def _setup_silence_duration_row(self, parent):
        """Setup silence duration row"""
        silence_frame = tk.Frame(parent)
        silence_frame.pack(fill=tk.X, pady=2)

        tk.Label(silence_frame, text="Silence Duration (s):", width=20, anchor="w").pack(side=tk.LEFT)

        silence_control_frame = tk.Frame(silence_frame)
        silence_control_frame.pack(side=tk.RIGHT, fill=tk.X, expand=True)

        self.silence_duration_var = tk.DoubleVar(value=self.audio_manager.silence_duration)
        self.silence_duration_scale = tk.Scale(silence_control_frame, from_=0.5, to=5.0,
                                             resolution=0.1, orient=tk.HORIZONTAL,
                                             variable=self.silence_duration_var,
                                             command=self.update_silence_duration)
        self.silence_duration_scale.pack(fill=tk.X, expand=True)

    def _setup_vosk_parameters_row(self, parent):
        """Setup Vosk parameters controls"""
        vosk_frame = tk.Frame(parent)
        vosk_frame.pack(fill=tk.X, pady=5)
        
        # Title label
        tk.Label(vosk_frame, text="Vosk Engine Parameters:", font=("Arial", 10, "bold")).pack(anchor="w")
        
        # Max Alternatives
        max_alt_frame = tk.Frame(vosk_frame)
        max_alt_frame.pack(fill=tk.X, pady=1)
        tk.Label(max_alt_frame, text="Max Alternatives:", width=20, anchor="w").pack(side=tk.LEFT)
        max_alt_control = tk.Frame(max_alt_frame)
        max_alt_control.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        
        self.vosk_max_alt_var = tk.IntVar(value=self.config_manager.get_config_value('vosk_max_alternatives', 0))
        self.vosk_max_alt_scale = tk.Scale(max_alt_control, from_=0, to=5, 
                                          resolution=1, orient=tk.HORIZONTAL, 
                                          variable=self.vosk_max_alt_var,
                                          command=self.update_vosk_max_alternatives)
        self.vosk_max_alt_scale.pack(fill=tk.X, expand=True)
        
        # Beam
        beam_frame = tk.Frame(vosk_frame)
        beam_frame.pack(fill=tk.X, pady=1)
        tk.Label(beam_frame, text="Beam (selectivity):", width=20, anchor="w").pack(side=tk.LEFT)
        beam_control = tk.Frame(beam_frame)
        beam_control.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        
        self.vosk_beam_var = tk.IntVar(value=self.config_manager.get_config_value('vosk_beam', 20))
        self.vosk_beam_scale = tk.Scale(beam_control, from_=10, to=30, 
                                       resolution=1, orient=tk.HORIZONTAL, 
                                       variable=self.vosk_beam_var,
                                       command=self.update_vosk_beam)
        self.vosk_beam_scale.pack(fill=tk.X, expand=True)
        
        # Lattice Beam
        lattice_frame = tk.Frame(vosk_frame)
        lattice_frame.pack(fill=tk.X, pady=1)
        tk.Label(lattice_frame, text="Lattice Beam:", width=20, anchor="w").pack(side=tk.LEFT)
        lattice_control = tk.Frame(lattice_frame)
        lattice_control.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        
        self.vosk_lattice_var = tk.IntVar(value=self.config_manager.get_config_value('vosk_lattice_beam', 8))
        self.vosk_lattice_scale = tk.Scale(lattice_control, from_=4, to=12, 
                                          resolution=1, orient=tk.HORIZONTAL, 
                                          variable=self.vosk_lattice_var,
                                          command=self.update_vosk_lattice_beam)
        self.vosk_lattice_scale.pack(fill=tk.X, expand=True)
        
        # Confidence Threshold
        confidence_frame = tk.Frame(vosk_frame)
        confidence_frame.pack(fill=tk.X, pady=1)
        tk.Label(confidence_frame, text="Confidence Threshold:", width=20, anchor="w").pack(side=tk.LEFT)
        confidence_control = tk.Frame(confidence_frame)
        confidence_control.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        
        self.vosk_confidence_var = tk.DoubleVar(value=self.config_manager.get_config_value('confidence_threshold', 280.0))
        self.vosk_confidence_scale = tk.Scale(confidence_control, from_=200.0, to=400.0, 
                                             resolution=10.0, orient=tk.HORIZONTAL, 
                                             variable=self.vosk_confidence_var,
                                             command=self.update_vosk_confidence_threshold)
        self.vosk_confidence_scale.pack(fill=tk.X, expand=True)
    
    def _setup_bubble_row(self, parent):
        """Setup bubble feature controls"""
        # Bubble enabled checkbox
        bubble_frame = tk.Frame(parent)
        bubble_frame.pack(fill=tk.X, pady=2)
        
        tk.Label(bubble_frame, text="Bubble Mode:", width=20, anchor="w").pack(side=tk.LEFT)
        
        bubble_control_frame = tk.Frame(bubble_frame)
        bubble_control_frame.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        
        config = self.config_manager.load_config()
        self.bubble_enabled_var = tk.BooleanVar(value=config.get("bubble_enabled", False))
        self.bubble_checkbox = tk.Checkbutton(bubble_control_frame, text="Auto-hide window", 
                                             variable=self.bubble_enabled_var,
                                             command=self.update_bubble_enabled)
        self.bubble_checkbox.pack(side=tk.LEFT)
        
        # Bubble silence timeout slider
        timeout_frame = tk.Frame(parent)
        timeout_frame.pack(fill=tk.X, pady=2)
        
        tk.Label(timeout_frame, text="Bubble Timeout (s):", width=20, anchor="w").pack(side=tk.LEFT)
        
        timeout_control_frame = tk.Frame(timeout_frame)
        timeout_control_frame.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        
        self.bubble_timeout_var = tk.DoubleVar(value=config.get("bubble_silence_timeout", 3.0))
        self.bubble_timeout_scale = tk.Scale(timeout_control_frame, from_=1.0, to=10.0,
                                           resolution=0.5, orient=tk.HORIZONTAL,
                                           variable=self.bubble_timeout_var,
                                           command=self.update_bubble_timeout)
        self.bubble_timeout_scale.pack(fill=tk.X, expand=True)
    
    def _setup_text_areas_in_pane(self):
        """Setup text areas within the text pane"""
        # Frame for text areas
        text_frame = tk.Frame(self.text_pane)
        text_frame.pack(pady=10, fill=tk.BOTH, expand=True)
        
        # Final results history (top)
        self.final_text = scrolledtext.ScrolledText(text_frame, wrap=tk.WORD, width=80, height=12)
        self.final_text.pack(fill=tk.BOTH, expand=True, pady=(0, 5))
        
        # Configure tags for final results
        self.final_text.tag_configure("final", foreground="black")
        self.final_text.tag_configure("timestamp", foreground="gray", font=("Arial", 8))
        
        # Rolling buffer for final results (max 15 entries)
        from collections import deque
        self.final_results_buffer = deque(maxlen=15)
        
        # Current partial text (bottom, smaller)
        self.partial_text = scrolledtext.ScrolledText(text_frame, wrap=tk.WORD, width=80, height=3)
        self.partial_text.pack(fill=tk.X, pady=(5, 0))
        
        # Configure tags for partial results
        self.partial_text.tag_configure("sent", foreground="gray")
        self.partial_text.tag_configure("unsent", foreground="black")
    
    def show_controls_view(self):
        """Switch to controls view"""
        if hasattr(self, 'text_pane'):
            self.text_pane.pack_forget()
        if hasattr(self, 'controls_pane'):
            self.controls_pane.pack(fill=tk.BOTH, expand=True)
        
        # Update button states
        self.controls_view_button.config(relief="sunken")
        self.text_view_button.config(relief="raised")
        self.current_view = "controls"
    
    def show_text_view(self):
        """Switch to text view"""
        if hasattr(self, 'controls_pane'):
            self.controls_pane.pack_forget()
        if hasattr(self, 'text_pane'):
            self.text_pane.pack(fill=tk.BOTH, expand=True)
        
        # Update button states
        self.controls_view_button.config(relief="raised")
        self.text_view_button.config(relief="sunken")
        self.current_view = "text"
    
    def _start_energy_display_updates(self):
        """Start updating audio energy display"""
        self.update_energy_display()
    
    def toggle_transcription(self):
        """Toggle transcription state"""
        self.audio_manager.toggle_transcription()
    
    def update_energy_threshold(self, value):
        """Update the energy threshold for UI color changes"""
        threshold = float(value)
        self.audio_manager.update_energy_threshold(threshold)
        self.config_manager.update_config_param("energy_threshold", threshold)
        logger.debug(f"Energy threshold updated to: {threshold}")

    def update_lookback_duration(self, value):
        """Update the lookback duration for speech detection"""
        duration = float(value)
        self.audio_manager.update_lookback_duration(duration)
        self.config_manager.update_config_param("lookback_duration", duration)
        logger.debug(f"Lookback duration updated to: {duration}s")

    def update_silence_duration(self, value):
        """Update the silence duration for speech detection"""
        duration = float(value)
        self.audio_manager.update_silence_duration(duration)
        self.config_manager.update_config_param("silence_duration", duration)
        logger.debug(f"Silence duration updated to: {duration}s")

    def update_vosk_max_alternatives(self, value):
        """Update Vosk max alternatives parameter"""
        max_alt = int(value)
        self.config_manager.update_config_param("vosk_max_alternatives", max_alt)
        # Update the active speech engine if it's available
        if self.app:
            self.app.update_vosk_max_alternatives(max_alt)
        logger.debug(f"Vosk max alternatives updated to: {max_alt}")
    
    def update_vosk_beam(self, value):
        """Update Vosk beam parameter"""
        beam = int(value)
        self.config_manager.update_config_param("vosk_beam", beam)
        # Update the active speech engine if it's available
        if self.app:
            self.app.update_vosk_beam(beam)
        logger.debug(f"Vosk beam updated to: {beam}")
    
    def update_vosk_lattice_beam(self, value):
        """Update Vosk lattice beam parameter"""
        lattice_beam = int(value)
        self.config_manager.update_config_param("vosk_lattice_beam", lattice_beam)
        # Update the active speech engine if it's available
        if self.app:
            self.app.update_vosk_lattice_beam(lattice_beam)
        logger.debug(f"Vosk lattice beam updated to: {lattice_beam}")
    
    def update_vosk_confidence_threshold(self, value):
        """Update Vosk confidence threshold parameter"""
        confidence = float(value)
        self.config_manager.update_config_param("confidence_threshold", confidence)
        # Update the active speech engine if it's available
        if self.app:
            self.app.update_vosk_confidence_threshold(confidence)
        logger.debug(f"Vosk confidence threshold updated to: {confidence:.2f}")
    
    
    
    def on_device_change(self, event=None):
        """Handle audio device change from dropdown"""
        try:
            selected_display_name = self.device_var.get()
            
            # Find the selected device info
            selected_device = None
            for display_name, device_id, device_name in self.available_devices:
                if display_name == selected_display_name:
                    selected_device = (display_name, device_id, device_name)
                    break
            
            if selected_device:
                display_name, device_id, device_name = selected_device
                logger.info(f"Device changed to: {device_name} (ID: {device_id})")
                
                # Update config with device name for consistency
                self.config_manager.update_config_param("audio_device", device_name.lower())
                
                # Show a message that restart is needed for device change
                logger.info("Device changed in config. Restart talkie to use the new device.")
                
                # Update the window title to show pending restart
                self.master.title("Talkie - Restart required for device change")
                
        except Exception as e:
            logger.error(f"Error changing audio device: {e}")
    
    def update_energy_display(self):
        """Update the audio energy display in real-time"""
        # Format energy value to be consistent width to prevent button size changes
        # Protect against NaN values
        raw_energy = self.audio_manager.current_audio_energy
        if raw_energy is None or not np.isfinite(raw_energy):
            energy_value = 0
        else:
            energy_value = int(max(0, min(99999, raw_energy)))  # Display max clamp only
        
        # Simple audio level display
        energy_text = f"Audio: {energy_value:5d}"
        
        # Simple color coding based on configurable energy threshold
        if energy_value > self.audio_manager.energy_threshold:
            self.energy_label.config(text=energy_text, fg="darkgreen")
        else:
            self.energy_label.config(text=energy_text, fg="darkred")
        
        # Update confidence display
        if self.app and hasattr(self.app, 'current_confidence'):
            confidence = self.app.current_confidence
            if confidence > 0:
                confidence_text = f"Conf: {confidence:.0f}"  # Show as integer for 250-400 range
                # Color coding based on confidence level (adjusted for 250-400 range)
                if confidence >= 350:
                    confidence_color = "darkgreen"  # High confidence
                elif confidence >= 300:
                    confidence_color = "orange"     # Medium confidence  
                else:
                    confidence_color = "darkred"    # Low confidence
                self.confidence_label.config(text=confidence_text, fg=confidence_color)
            else:
                self.confidence_label.config(text="Conf: --", fg="gray")
        else:
            self.confidence_label.config(text="Conf: --", fg="gray")
        
        # Schedule next update
        self.master.after(100, self.update_energy_display)
    
    def update_ui(self):
        """Update UI based on transcription state"""
        if self.audio_manager.transcribing:
            self.button.config(text="Stop Transcription", bg="lightgreen", fg="black", 
                              activebackground="mediumseagreen")
        else:
            self.button.config(text="Start Transcription", bg="lightcoral", fg="black",
                              activebackground="indianred")
    
    def update_partial_text(self, text):
        """Update partial text display with sent/unsent word styling"""
        self.partial_text.delete(1.0, tk.END)
        if text.strip():
            words = text.split()
            for word in words:
                if word.startswith('<sent>') and word.endswith('</sent>'):
                    self.partial_text.insert(tk.END, word[6:-7] + ' ', "sent")
                else:
                    self.partial_text.insert(tk.END, word + ' ', "unsent")
    
    def clear_partial_text(self):
        """Clear the partial text display"""
        self.partial_text.delete(1.0, tk.END)
    
    def add_final_result(self, text):
        """Add a final result to the rolling buffer and display"""
        import time
        
        if not text.strip():
            return
            
        # Add timestamp
        timestamp = time.strftime("%H:%M:%S")
        
        # Add to rolling buffer
        self.final_results_buffer.append(f"[{timestamp}] {text.strip()}")
        
        # Update display
        self._refresh_final_results_display()
    
    def _refresh_final_results_display(self):
        """Refresh the final results display from buffer"""
        self.final_text.delete(1.0, tk.END)
        
        for i, result in enumerate(self.final_results_buffer):
            if i > 0:
                self.final_text.insert(tk.END, "\n")
            
            # Parse timestamp and text
            if result.startswith("[") and "] " in result:
                bracket_end = result.find("] ")
                timestamp = result[1:bracket_end]
                text = result[bracket_end + 2:]
                
                self.final_text.insert(tk.END, f"[{timestamp}] ", "timestamp")
                self.final_text.insert(tk.END, text, "final")
            else:
                self.final_text.insert(tk.END, result, "final")
        
        # Auto-scroll to bottom
        self.final_text.see(tk.END)
    
    def quit_app(self):
        """Handle application quit request"""
        logger.info("Quit option selected. Initiating shutdown...")
        # This will be connected to main cleanup function
        if hasattr(self, 'quit_callback') and self.quit_callback:
            self.quit_callback()
    
    def set_quit_callback(self, callback):
        """Set the callback for quit operations"""
        self.quit_callback = callback
    
    def _restore_window_position(self):
        """Restore window position from configuration"""
        try:
            config = self.config_manager.load_config()
            x = config.get("window_x", 100)
            y = config.get("window_y", 100)
            self.master.geometry(f"800x400+{x}+{y}")
            logger.debug(f"Restored window position to ({x}, {y})")
        except Exception as e:
            logger.error(f"Error restoring window position: {e}")
            self.master.geometry("800x400+100+100")  # Fallback position
    
    def _save_window_position(self):
        """Save current window position to configuration"""
        try:
            # Get current window position
            geometry = self.master.geometry()
            # Parse geometry string like "800x400+150+100"
            if '+' in geometry:
                parts = geometry.split('+')
                if len(parts) >= 3:
                    x = int(parts[1])
                    y = int(parts[2])
                    self.config_manager.update_config_param("window_x", x)
                    self.config_manager.update_config_param("window_y", y)
                    logger.debug(f"Saved window position ({x}, {y})")
        except Exception as e:
            logger.error(f"Error saving window position: {e}")
    
    def _on_window_configure(self, event):
        """Handle window configuration changes (move/resize)"""
        # Only save position for the main window, not child widgets
        if event.widget == self.master:
            # Small delay to avoid saving too frequently during dragging
            self.master.after(500, self._save_window_position)
    
    def _on_window_close(self):
        """Handle window close event"""
        self._save_window_position()
        self.quit_app()
    
    def _initialize_bubble_feature(self):
        """Initialize bubble feature state and timers"""
        self.bubble_lowered = False
        self.bubble_hide_timer = None
        self.last_voice_activity_time = None
        self.mouse_in_window = False
        self.last_mouse_activity = None
        
        # Load initial bubble configuration
        config = self.config_manager.load_config()
        self.bubble_enabled = config.get("bubble_enabled", False)
        self.bubble_silence_timeout = config.get("bubble_silence_timeout", 3.0)
        
        # Setup mouse tracking for bubble feature
        self._setup_mouse_tracking()
        
        # Start bubble monitoring if enabled
        if self.bubble_enabled:
            self._start_bubble_monitoring()
    
    def update_bubble_enabled(self):
        """Update bubble enabled state"""
        self.bubble_enabled = self.bubble_enabled_var.get()
        self.config_manager.update_config_param("bubble_enabled", self.bubble_enabled)
        
        if self.bubble_enabled:
            self._start_bubble_monitoring()
            logger.info("Bubble mode enabled - window will auto-hide after silence")
        else:
            self._stop_bubble_monitoring()
            self._raise_window()
            logger.info("Bubble mode disabled")
    
    def update_bubble_timeout(self, value):
        """Update bubble silence timeout"""
        self.bubble_silence_timeout = float(value)
        self.config_manager.update_config_param("bubble_silence_timeout", self.bubble_silence_timeout)
        logger.debug(f"Bubble timeout updated to: {self.bubble_silence_timeout}s")
    
    def _start_bubble_monitoring(self):
        """Start monitoring for bubble hide/show behavior"""
        import time
        # Initialize voice activity time to current time so we can start timing silence
        self.last_voice_activity_time = time.time()
        self._update_bubble_state()
    
    def _stop_bubble_monitoring(self):
        """Stop bubble monitoring and cancel timers"""
        if self.bubble_hide_timer:
            self.master.after_cancel(self.bubble_hide_timer)
            self.bubble_hide_timer = None
    
    def _update_bubble_state(self):
        """Update bubble state based on audio activity"""
        if not self.bubble_enabled:
            return
        
        import time
        current_time = time.time()
        
        audio_energy = self.audio_manager.current_audio_energy
        has_voice = audio_energy > self.audio_manager.energy_threshold  # Configurable threshold for bubble feature
        
        # Debug logging every 50 cycles (5 seconds)
        if not hasattr(self, '_bubble_debug_count'):
            self._bubble_debug_count = 0
        self._bubble_debug_count += 1
        
        if self._bubble_debug_count % 50 == 0:
            silence_time = current_time - self.last_voice_activity_time if self.last_voice_activity_time else 0
        
        # Check if there's current voice activity
        if has_voice:
            self.last_voice_activity_time = current_time
            # Only raise if currently lowered
            if self.bubble_lowered:
                self._raise_window()
            
            # Cancel any pending hide timer
            if self.bubble_hide_timer:
                self.master.after_cancel(self.bubble_hide_timer)
                self.bubble_hide_timer = None
        else:
            # No voice activity - check if we should lower
            if self.last_voice_activity_time and not self.mouse_in_window:
                silence_duration = current_time - self.last_voice_activity_time
                if silence_duration > self.bubble_silence_timeout and not self.bubble_lowered:
                    self._lower_window()
            elif self.mouse_in_window and self.bubble_lowered:
                self._raise_window()
        
        # Schedule next update
        self.master.after(100, self._update_bubble_state)
    
    def _raise_window(self):
        """Raise the window to top of window stack (bubble up)"""
        if self.bubble_lowered:
            # Raise to top of window stack without taking focus
            try:
                self.master.attributes('-topmost', True)
                self.master.after_idle(lambda: self.master.attributes('-topmost', False))
                self.bubble_lowered = False
                logger.debug("Bubble: Window raised to top")
            except Exception as e:
                logger.error(f"Error raising window: {e}")
    
    def _lower_window(self):
        """Lower the window to bottom of window stack (bubble down)"""
        if not self.bubble_lowered:
            # Try multiple approaches to ensure window is lowered
            try:
                # Method 1: Standard lower
                self.master.lower()
                
                # Method 2: Force update and lower again (helps with some window managers)
                self.master.update()
                self.master.lower()
                
                # Method 3: Temporarily set topmost false (helps reset window state)
                self.master.attributes('-topmost', False)
                self.master.lower()
                
                self.bubble_lowered = True
            except Exception as e:
                logger.error(f"Error lowering window: {e}")
    
    def _on_mouse_enter(self, event):
        """Handle mouse entering the window"""
        if not self.mouse_in_window:
            self.mouse_in_window = True
            if self.bubble_enabled:
                logger.debug("Bubble: Mouse entered - preventing lower")
                if self.bubble_lowered:
                    self._raise_window()
    
    def _on_mouse_leave(self, event):
        """Handle mouse leaving the window"""
        self.mouse_in_window = False
        if self.bubble_enabled:
            logger.debug("Bubble: Mouse left - lowering allowed")
            import time
            self.last_voice_activity_time = time.time()
    
    def _setup_mouse_tracking(self):
        """Setup mouse tracking for bubble feature"""
        logger.info("Setting up mouse tracking for bubble feature")
        
        # Simple Enter/Leave events
        self.master.bind("<Enter>", self._on_mouse_enter)
        self.master.bind("<Leave>", self._on_mouse_leave)
        
        logger.info("Mouse tracking setup completed with Enter/Leave events")
    
