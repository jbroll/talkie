#!/usr/bin/env python3
"""
Simple test to check voice detection behavior
"""

import numpy as np
import sounddevice as sd
import time
import sys
import os
sys.path.append('src')

from audio_manager import AudioManager

def test_voice_detection():
    """Test voice detection with different modes"""
    
    # Initialize AudioManager with default settings
    audio_mgr = AudioManager(voice_threshold=50.0, vad_mode="simple")
    
    print("Testing audio input and voice detection...")
    print("Speak into microphone to see voice detection behavior")
    print("Press Ctrl+C to exit")
    
    def audio_callback(indata, frames, time_info, status):
        audio_np = indata.flatten()
        audio_mgr.analyze_audio_frame(audio_np)
        
        # Print values every 10 callbacks (~1 second)
        if not hasattr(audio_callback, 'counter'):
            audio_callback.counter = 0
        audio_callback.counter += 1
        
        if audio_callback.counter % 10 == 0:
            energy = audio_mgr.current_audio_energy
            voice_detected = audio_mgr.voice_detected
            threshold = audio_mgr.voice_threshold
            vad_mode = audio_mgr.vad_mode
            
            print(f"Energy: {energy:8.2f} | Threshold: {threshold:6.1f} | Voice: {voice_detected} | Mode: {vad_mode}")
    
    try:
        # Start audio stream
        with sd.InputStream(callback=audio_callback, channels=1, samplerate=16000, blocksize=1600):
            while True:
                time.sleep(0.1)
    except KeyboardInterrupt:
        print("\nStopping...")

if __name__ == "__main__":
    test_voice_detection()