#!/home/john/src/talkie/bin/python3

import logging
import numpy as np
import queue
import sounddevice as sd
import time
from collections import deque
from pathlib import Path

from JSONFileMonitor import JSONFileMonitor

logger = logging.getLogger(__name__)

class AudioManager:
    """Manages audio input, device selection, and voice activity detection"""
    
    def __init__(self, speech_timeout=3.0, energy_threshold=50.0):
        self.speech_timeout = speech_timeout
        self.energy_threshold = energy_threshold
        
        # Audio stream state
        self.transcribing = False
        self.current_audio_energy = 0.0  # Keep for display only
        self.last_speech_time = None
        
        
        # Queue for audio data
        self.q = None
        
        # File monitor for state changes
        self.file_monitor = None
        self.on_transcription_change_callback = None
        self.on_speech_end_callback = None
        
    
    def set_transcribing(self, state):
        """Set transcription state and clear queue if stopping"""
        self.transcribing = state
        logger.info(f"Transcription: {'ON' if self.transcribing else 'OFF'}")
        
        if not self.transcribing and self.q:
            # Clear the queue when transcription is turned off
            while not self.q.empty():
                try:
                    self.q.get_nowait()
                except queue.Empty:
                    break
            self.speech_start_time = None
        
        # Notify GUI of state change
        if self.on_transcription_change_callback:
            self.on_transcription_change_callback()
    
    def toggle_transcription(self):
        """Toggle transcription state"""
        self.set_transcribing(not self.transcribing)
        if self.on_transcription_change_callback:
            self.on_transcription_change_callback()
    
    def set_transcription_change_callback(self, callback):
        """Set callback for transcription state changes"""
        self.on_transcription_change_callback = callback
    
    def set_speech_end_callback(self, callback):
        """Set callback for when speech detection ends"""
        self.on_speech_end_callback = callback
    
    
    def update_speech_timeout(self, timeout):
        """Update speech timeout duration"""
        self.speech_timeout = float(timeout)
        logger.debug(f"Speech timeout updated to: {self.speech_timeout}s")
    
    def update_energy_threshold(self, threshold):
        """Update energy threshold for UI display"""
        self.energy_threshold = float(threshold)
        logger.debug(f"Energy threshold updated to: {self.energy_threshold}")
    
    def list_audio_devices(self):
        """List available audio input devices"""
        logger.info("Available audio input devices:")
        devices = sd.query_devices()
        for i, device in enumerate(devices):
            if device['max_input_channels'] > 0:
                logger.info(f"{i}: {device['name']}")
        return devices
    
    def get_input_devices_for_ui(self):
        """Get a list of input devices formatted for UI dropdown"""
        devices = sd.query_devices()
        input_devices = []
        for i, device in enumerate(devices):
            if device['max_input_channels'] > 0:
                display_name = f"{device['name']} (ID: {i})"
                input_devices.append((display_name, i, device['name']))
        return input_devices
    
    def get_supported_samplerates(self, device_id):
        """Get supported sample rates for a device"""
        device_info = sd.query_devices(device_id, 'input')
        try:
            supported_rates = [
                int(rate) for rate in device_info['default_samplerate'].split(',')
            ]
        except AttributeError:
            supported_rates = [int(device_info['default_samplerate'])]
        
        logger.debug(f"Supported sample rates for device {device_id}: {supported_rates}")
        return supported_rates
    
    def select_audio_device(self, device_substring=None, config=None):
        """Select audio device by name or ID, with config fallback"""
        devices = self.list_audio_devices()
        
        # If no device specified, try to use config
        if not device_substring and config:
            device_substring = config.get("audio_device")
            logger.info(f"Using audio device from config: {device_substring}")
        
        if device_substring:
            device_id = None
            device_info = None
            
            # First try numeric input
            try:
                device_id = int(device_substring)
                if 0 <= device_id < len(devices) and devices[device_id]['max_input_channels'] > 0:
                    device_info = devices[device_id]
                    logger.info(f"Selected device by number: {device_info['name']}")
                else:
                    logger.error(f"Device {device_id} not found or has no input channels.")
                    return None, None
            except ValueError:
                # Not a number, try name matching
                device_aliases = {
                    'pulse': 'pulse',
                    'default': 'default',
                    'system': 'sysdefault',
                    'sys': 'sysdefault'
                }
                
                search_term = device_aliases.get(device_substring.lower(), device_substring.lower())
                
                matching_devices = [
                    (i, device) for i, device in enumerate(devices)
                    if device['max_input_channels'] > 0 and search_term in device['name'].lower()
                ]
                
                if matching_devices:
                    if len(matching_devices) > 1:
                        logger.info("Multiple matching devices found:")
                        for i, device in matching_devices:
                            logger.info(f"{i}: {device['name']}")
                        # Auto-select exact match or first match
                        exact_matches = [d for d in matching_devices if search_term == d[1]['name'].lower()]
                        if exact_matches:
                            device_id, device_info = exact_matches[0]
                            logger.info(f"Selected exact match: {device_info['name']}")
                        else:
                            device_id, device_info = matching_devices[0]
                            logger.info(f"Selected first match: {device_info['name']}")
                    else:
                        device_id, device_info = matching_devices[0]
                    
                    logger.info(f"Selected device: {device_info['name']}")
                else:
                    logger.error(f"No device matching '{device_substring}' found.")
                    return None, None
        else:
            # No device specified and no config
            logger.error("No audio device specified. Use --device <name> or configure in ~/.talkie.conf")
            logger.info("Available devices:")
            for i, device in enumerate(devices):
                if device['max_input_channels'] > 0:
                    logger.info(f"  {i}: {device['name']}")
            logger.info("Example: ./talkie.sh --device pulse")
            return None, None
        
        supported_rates = self.get_supported_samplerates(device_id)
        if not supported_rates:
            logger.error("No supported sample rates found for this device.")
            return None, None
        
        # Prefer rates <= 16000, otherwise use minimum
        preferred_rates = [r for r in supported_rates if r <= 16000]
        if preferred_rates:
            samplerate = max(preferred_rates)
        else:
            samplerate = min(supported_rates)
        logger.info(f"Selected sample rate: {samplerate} Hz")
        
        return device_id, samplerate
    
    def audio_callback(self, indata, frames, time_info, status):
        """Simple audio stream callback - just feed audio to speech engine"""
        try:
            audio_raw = indata.flatten()  # Keep original int16 data for speech engines
            # Simple energy calculation for UI display only
            audio_normalized = audio_raw.astype(np.float32) / 32768.0
            self.current_audio_energy = np.abs(audio_normalized).mean() * 1000  # Scale for display
        except Exception as e:
            logger.error(f"Error processing audio in callback: {e}")
            self.current_audio_energy = 0.0
            return
        
        if not self.transcribing or not self.q:
            return
            
        # Stream everything to Vosk - let it handle all VAD
        if not self.q.full():
            self.q.put(audio_raw.tobytes())
    
    def setup_file_monitor(self, on_file_change_callback):
        """Setup file monitor for transcription state changes"""
        self.file_monitor = JSONFileMonitor(Path.home() / ".talkie", on_file_change_callback)
        self.file_monitor.start()
    
    def cleanup_file_monitor(self):
        """Clean up file monitor"""
        if self.file_monitor:
            self.file_monitor.stop()
    
        
    def initialize_queue(self, queue_size):
        """Initialize the audio processing queue"""
        self.q = queue.Queue(maxsize=queue_size)