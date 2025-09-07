#!/home/john/src/talkie/bin/python3

import logging
import tkinter as tk
from tkinter import scrolledtext, ttk

logger = logging.getLogger(__name__)

class TalkieGUI:
    """Manages the Tkinter GUI interface for Talkie"""
    
    def __init__(self, master, audio_manager, config_manager, text_processor):
        self.master = master
        self.audio_manager = audio_manager
        self.config_manager = config_manager
        self.text_processor = text_processor
        
        # Set up callbacks
        self.audio_manager.set_transcription_change_callback(self.update_ui)
        
        self._setup_ui()
        self._setup_device_selection()
        self._start_energy_display_updates()
    
    def _setup_ui(self):
        """Initialize the main UI components"""
        self.master.title("Talkie")
        
        # Bind Alt+Q to quit_app function
        self.master.bind("<Alt-q>", lambda event: self.quit_app())
        
        # Button row frame
        button_frame = tk.Frame(self.master)
        button_frame.pack(fill=tk.X, pady=10)
        
        # Main transcription toggle button (flush left)
        self.button = tk.Button(button_frame, text="Start Transcription", command=self.toggle_transcription)
        self.button.pack(side=tk.LEFT, pady=0)
        
        # Audio energy display (center) - styled like a button, same row
        self.energy_label = tk.Label(button_frame, text="Audio: 0", 
                                    relief="raised", bd=2, 
                                    padx=10, pady=5, 
                                    font=("Arial", 10))
        self.energy_label.pack(side=tk.LEFT, expand=True, padx=10, pady=0)
        
        # Quit button (flush right)
        self.quit_button = tk.Button(button_frame, text="Quit", command=self.quit_app)
        self.quit_button.pack(side=tk.RIGHT, pady=0)
        
        # All controls in single column
        self._setup_controls_column()
        
        # Text display areas
        self._setup_text_areas()
        
        # Status label
        self.status_label = tk.Label(self.master, text="Transcription: OFF")
        self.status_label.pack(pady=5)
    
    def _setup_device_frame(self):
        """Setup audio device selection frame"""
        self.device_frame = tk.Frame(self.master)
        self.device_frame.pack(pady=5)
        
        tk.Label(self.device_frame, text="Audio Device:").pack(side=tk.LEFT)
        
        # Get available devices
        self.available_devices = self.audio_manager.get_input_devices_for_ui()
        device_names = [device[0] for device in self.available_devices]
        
        self.device_var = tk.StringVar()
        self.device_combo = ttk.Combobox(self.device_frame, 
                                        textvariable=self.device_var,
                                        values=device_names,
                                        state="readonly",
                                        width=30)
        self.device_combo.pack(side=tk.LEFT, padx=5)
        self.device_combo.bind("<<ComboboxSelected>>", self.on_device_change)
    
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
    
    def _setup_controls_frame(self):
        """Setup voice threshold controls frame"""
        self.controls_frame = tk.Frame(self.master)
        self.controls_frame.pack(pady=5)
        
        # Voice threshold slider
        tk.Label(self.controls_frame, text="Voice Threshold:").pack(side=tk.LEFT)
        self.threshold_var = tk.DoubleVar(value=self.audio_manager.voice_threshold)
        self.threshold_scale = tk.Scale(self.controls_frame, from_=10, to=300, 
                                       resolution=5, orient=tk.HORIZONTAL, 
                                       variable=self.threshold_var,
                                       command=self.update_threshold)
        self.threshold_scale.pack(side=tk.LEFT, padx=5)
        
        # Audio energy display
        self.energy_label = tk.Label(self.controls_frame, text="Audio: 0.000")
        self.energy_label.pack(side=tk.LEFT, padx=10)
    
    def _setup_controls_frame2(self):
        """Setup second row of controls"""
        self.controls_frame2 = tk.Frame(self.master)
        self.controls_frame2.pack(pady=5)
        
        # Silence trailing duration slider
        tk.Label(self.controls_frame2, text="Silence Trailing (s):").pack(side=tk.LEFT)
        self.silence_var = tk.DoubleVar(value=self.audio_manager.silence_trailing_duration)
        self.silence_scale = tk.Scale(self.controls_frame2, from_=0.1, to=2.0, 
                                     resolution=0.1, orient=tk.HORIZONTAL, 
                                     variable=self.silence_var,
                                     command=self.update_silence_duration)
        self.silence_scale.pack(side=tk.LEFT, padx=5)
        
        # Speech timeout slider
        tk.Label(self.controls_frame2, text="Speech Timeout (s):").pack(side=tk.LEFT)
        self.timeout_var = tk.DoubleVar(value=self.audio_manager.speech_timeout)
        self.timeout_scale = tk.Scale(self.controls_frame2, from_=1.0, to=10.0, 
                                     resolution=0.5, orient=tk.HORIZONTAL, 
                                     variable=self.timeout_var,
                                     command=self.update_speech_timeout)
        self.timeout_scale.pack(side=tk.LEFT, padx=5)
        
        # Third row of controls for lookback buffer
        self.controls_frame3 = tk.Frame(self.master)
        self.controls_frame3.pack(pady=5)
        
        # Lookback frames slider
        tk.Label(self.controls_frame3, text="Lookback Frames:").pack(side=tk.LEFT)
        self.lookback_var = tk.IntVar(value=self.audio_manager.lookback_frames)
        self.lookback_scale = tk.Scale(self.controls_frame3, from_=1, to=20, 
                                      resolution=1, orient=tk.HORIZONTAL, 
                                      variable=self.lookback_var,
                                      command=self.update_lookback_frames)
        self.lookback_scale.pack(side=tk.LEFT, padx=5)
        
        # Info label for lookback buffer
        self.lookback_info = tk.Label(self.controls_frame3, text="(0.5s @ 44kHz)", fg="gray")
        self.lookback_info.pack(side=tk.LEFT, padx=5)
    
    def _setup_text_areas(self):
        """Setup dual text display areas"""
        from collections import deque
        
        # Frame for text areas
        text_frame = tk.Frame(self.master)
        text_frame.pack(pady=10, fill=tk.BOTH, expand=True)
        
        # Final results history (top)
        self.final_text = scrolledtext.ScrolledText(text_frame, wrap=tk.WORD, width=80, height=12)
        self.final_text.pack(fill=tk.BOTH, expand=True, pady=(0, 5))
        
        # Configure tags for final results
        self.final_text.tag_configure("final", foreground="black")
        self.final_text.tag_configure("timestamp", foreground="gray", font=("Arial", 8))
        
        # Rolling buffer for final results (max 15 entries)
        self.final_results_buffer = deque(maxlen=15)
        
        # Current partial text (bottom, smaller)
        self.partial_text = scrolledtext.ScrolledText(text_frame, wrap=tk.WORD, width=80, height=3)
        self.partial_text.pack(fill=tk.X, pady=(5, 0))
        
        # Configure tags for partial results
        self.partial_text.tag_configure("sent", foreground="gray")
        self.partial_text.tag_configure("unsent", foreground="black")
    
    def _setup_controls_column(self):
        """Setup all controls in a single column with labels left, controls right"""
        # Main controls frame
        controls_container = tk.Frame(self.master)
        controls_container.pack(pady=10, padx=20, fill=tk.X)
        
        # Audio Device row
        device_frame = tk.Frame(controls_container)
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
        
        # Set current device from config
        self._setup_device_selection()
        
        # Voice Threshold row
        threshold_frame = tk.Frame(controls_container)
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
        
        # Silence Trailing Duration row
        silence_frame = tk.Frame(controls_container)
        silence_frame.pack(fill=tk.X, pady=2)
        
        tk.Label(silence_frame, text="Silence Trailing (s):", width=20, anchor="w").pack(side=tk.LEFT)
        
        silence_control_frame = tk.Frame(silence_frame)
        silence_control_frame.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        
        self.silence_var = tk.DoubleVar(value=self.audio_manager.silence_trailing_duration)
        self.silence_scale = tk.Scale(silence_control_frame, from_=0.1, to=2.0, 
                                     resolution=0.1, orient=tk.HORIZONTAL, 
                                     variable=self.silence_var,
                                     command=self.update_silence_duration)
        self.silence_scale.pack(fill=tk.X, expand=True)
        
        # Speech Timeout row
        timeout_frame = tk.Frame(controls_container)
        timeout_frame.pack(fill=tk.X, pady=2)
        
        tk.Label(timeout_frame, text="Speech Timeout (s):", width=20, anchor="w").pack(side=tk.LEFT)
        
        timeout_control_frame = tk.Frame(timeout_frame)
        timeout_control_frame.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        
        self.timeout_var = tk.DoubleVar(value=self.audio_manager.speech_timeout)
        self.timeout_scale = tk.Scale(timeout_control_frame, from_=1.0, to=10.0, 
                                     resolution=0.5, orient=tk.HORIZONTAL, 
                                     variable=self.timeout_var,
                                     command=self.update_speech_timeout)
        self.timeout_scale.pack(fill=tk.X, expand=True)
        
        # Lookback Frames row
        lookback_frame = tk.Frame(controls_container)
        lookback_frame.pack(fill=tk.X, pady=2)
        
        tk.Label(lookback_frame, text="Lookback Frames (ms):", width=20, anchor="w").pack(side=tk.LEFT)
        
        lookback_control_frame = tk.Frame(lookback_frame)
        lookback_control_frame.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        
        # Convert frames to milliseconds for display
        initial_ms = self.audio_manager.lookback_frames * 100
        self.lookback_var = tk.IntVar(value=initial_ms)
        self.lookback_scale = tk.Scale(lookback_control_frame, from_=100, to=2000, 
                                      resolution=100, orient=tk.HORIZONTAL, 
                                      variable=self.lookback_var,
                                      command=self.update_lookback_frames)
        self.lookback_scale.pack(fill=tk.X, expand=True)
    
    def _start_energy_display_updates(self):
        """Start updating audio energy display"""
        self.update_energy_display()
    
    def toggle_transcription(self):
        """Toggle transcription state"""
        self.audio_manager.toggle_transcription()
    
    def update_threshold(self, value):
        """Update the global voice threshold when slider changes"""
        threshold = float(value)
        self.audio_manager.update_voice_threshold(threshold)
        self.config_manager.update_config_param("voice_threshold", threshold)
        logger.debug(f"Voice threshold updated to: {threshold}")
    
    def update_silence_duration(self, value):
        """Update the global silence trailing duration when slider changes"""
        duration = float(value)
        self.audio_manager.update_silence_duration(duration)
        self.config_manager.update_config_param("silence_trailing_duration", duration)
        logger.debug(f"Silence trailing duration updated to: {duration}s")
    
    def update_speech_timeout(self, value):
        """Update the global speech timeout when slider changes"""
        timeout = float(value)
        self.audio_manager.update_speech_timeout(timeout)
        self.config_manager.update_config_param("speech_timeout", timeout)
        logger.debug(f"Speech timeout updated to: {timeout}s")
    
    def update_lookback_frames(self, value):
        """Update the lookback buffer size when slider changes"""
        duration_ms = int(value)
        frames = duration_ms // 100  # Convert milliseconds back to frames
        self.audio_manager.update_lookback_frames(frames)
        self.config_manager.update_config_param("lookback_frames", frames)
        
        logger.debug(f"Lookback buffer updated to: {duration_ms}ms ({frames} frames)")
    
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
        # Update energy display with color coding (show as integer for int16 audio)
        energy_text = f"Audio: {int(self.audio_manager.current_audio_energy)}"
        if self.audio_manager.current_audio_energy > self.audio_manager.voice_threshold:
            self.energy_label.config(text=energy_text, fg="green")  # Voice detected
        else:
            self.energy_label.config(text=energy_text, fg="red")    # Silence
        
        # Schedule next update
        self.master.after(100, self.update_energy_display)
    
    def update_ui(self):
        """Update UI based on transcription state"""
        if self.audio_manager.transcribing:
            self.button.config(text="Stop Transcription")
            self.status_label.config(text="Transcription: ON")
        else:
            self.button.config(text="Start Transcription")
            self.status_label.config(text="Transcription: OFF")
    
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