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
    
    def __init__(self, voice_threshold=50.0, silence_trailing_duration=0.5, speech_timeout=3.0, lookback_frames=5):
        self.voice_threshold = voice_threshold
        self.silence_trailing_duration = silence_trailing_duration
        self.speech_timeout = speech_timeout
        self.lookback_frames = lookback_frames  # Number of frames to buffer before speech
        
        # Audio stream state
        self.transcribing = False
        self.current_audio_energy = 0.0
        self.speech_start_time = None
        self.last_speech_time = None
        self.silence_frames_sent = 0
        self.max_silence_frames = 0
        self.callback_count = 0
        
        # Circular buffer for pre-speech audio (lookback buffer)
        self.lookback_buffer = deque(maxlen=self.lookback_frames)
        logger.debug(f"Initialized lookback buffer with {self.lookback_frames} frames")
        
        # Queue for audio data
        self.q = None
        
        # File monitor for state changes
        self.file_monitor = None
        self.on_transcription_change_callback = None
    
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
            logger.debug("Audio queue cleared")
    
    def toggle_transcription(self):
        """Toggle transcription state"""
        self.set_transcribing(not self.transcribing)
        if self.on_transcription_change_callback:
            self.on_transcription_change_callback()
    
    def set_transcription_change_callback(self, callback):
        """Set callback for transcription state changes"""
        self.on_transcription_change_callback = callback
    
    def update_voice_threshold(self, threshold):
        """Update voice activity detection threshold"""
        self.voice_threshold = float(threshold)
        logger.debug(f"Voice threshold updated to: {self.voice_threshold}")
    
    def update_silence_duration(self, duration, block_duration=0.1):
        """Update silence trailing duration and recalculate frames"""
        self.silence_trailing_duration = float(duration)
        self.max_silence_frames = int(self.silence_trailing_duration / block_duration)
        logger.debug(f"Silence trailing duration updated to: {self.silence_trailing_duration}s ({self.max_silence_frames} frames)")
    
    def update_speech_timeout(self, timeout):
        """Update speech timeout duration"""
        self.speech_timeout = float(timeout)
        logger.debug(f"Speech timeout updated to: {self.speech_timeout}s")
    
    def update_lookback_frames(self, frames):
        """Update the number of lookback frames for pre-speech capture"""
        self.lookback_frames = int(frames)
        self.lookback_buffer = deque(maxlen=self.lookback_frames)
        logger.debug(f"Updated lookback buffer to {self.lookback_frames} frames")
    
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
        """Audio stream callback for voice activity detection and audio processing"""
        # Always update current_audio_energy for UI display
        try:
            audio_np = indata.flatten()
            audio_energy = np.abs(audio_np).mean()
            self.current_audio_energy = audio_energy
            
            # Debug logging (throttled)
            self.callback_count += 1
            
            if self.callback_count % 50 == 0:
                logger.info(f"Audio callback {self.callback_count}: energy={audio_energy:.1f}, transcribing={self.transcribing}, threshold={self.voice_threshold}")
        except Exception as e:
            logger.error(f"Error processing audio in callback: {e}")
            self.current_audio_energy = 0.0
        
        if status:
            logger.debug(f"Audio status: {status}")
        
        if self.transcribing and self.q and not self.q.full():
            current_time = time.time()
            
            if audio_energy > self.voice_threshold:
                # Voice detected
                if self.speech_start_time is None:
                    # Transition from silence to speech - send entire lookback buffer first
                    frames_sent = 0
                    for buffered_frame in self.lookback_buffer:
                        self.q.put(buffered_frame)
                        frames_sent += 1
                    if frames_sent > 0:
                        logger.debug(f"Sent {frames_sent} lookback frames for word leading edge")
                    self.speech_start_time = current_time
                    logger.debug("Speech started")
                self.last_speech_time = current_time
                self.silence_frames_sent = 0
                self.q.put(audio_np.tobytes())
            else:
                # No voice detected
                if self.speech_start_time is not None and self.silence_frames_sent < self.max_silence_frames:
                    # Send trailing silence for utterance completion
                    self.silence_frames_sent += 1
                    silent_frame = np.zeros_like(audio_np)
                    self.q.put(silent_frame.tobytes())
                    logger.debug(f"Sending silence frame {self.silence_frames_sent}/{self.max_silence_frames}")
                    
                    if self.silence_frames_sent >= self.max_silence_frames:
                        logger.debug("Silence trailing complete")
                        self.speech_start_time = None
                else:
                    # Pure silence - reset speech timing
                    if self.speech_start_time is not None:
                        logger.debug(f"Voice activity ended, energy: {audio_energy:.4f}")
                        self.speech_start_time = None
                
                # Always store audio frames in lookback buffer during silence
                if audio_energy <= self.voice_threshold:
                    self.lookback_buffer.append(audio_np.tobytes())
        elif self.transcribing and self.q and self.q.full():
            logger.debug("Audio queue is full, dropping audio data")
    
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