#!/usr/bin/env python3
"""
Test Vosk's built-in VAD by sending continuous audio stream
"""

import numpy as np
import sounddevice as sd
import time
import json
import sys
import os
sys.path.append('src')

# Import Vosk directly
try:
    import vosk
    vosk.SetLogLevel(-1)
    print("✓ Vosk imported successfully")
except ImportError:
    print("✗ Vosk not available")
    exit(1)

def test_vosk_builtin_vad():
    """Test continuous streaming to Vosk with built-in VAD"""
    
    # Initialize Vosk recognizer
    model_path = "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
    if not os.path.exists(model_path):
        print(f"✗ Model not found at {model_path}")
        return
    
    print(f"Loading Vosk model from {model_path}")
    model = vosk.Model(model_path)
    recognizer = vosk.KaldiRecognizer(model, 16000)
    recognizer.SetWords(True)
    print("✓ Vosk recognizer initialized")
    
    print("\nStarting continuous audio stream to Vosk...")
    print("Speak into microphone - Vosk will handle VAD internally")
    print("Press Ctrl+C to exit\n")
    
    frame_count = 0
    results = []
    
    def audio_callback(indata, frames, time_info, status):
        nonlocal frame_count, results
        
        # Convert to int16 for Vosk
        audio_int16 = (indata.flatten() * 32767).astype(np.int16)
        audio_bytes = audio_int16.tobytes()
        
        frame_count += 1
        
        # Send EVERY frame to Vosk - let it handle VAD
        if recognizer.AcceptWaveform(audio_bytes):
            # Vosk detected end of utterance
            result = json.loads(recognizer.Result())
            if result.get('text'):
                print(f"FINAL: '{result['text']}' (confidence: {result.get('confidence', 'N/A')})")
                results.append(result['text'])
        else:
            # Get partial result if available
            partial = json.loads(recognizer.PartialResult())
            if partial.get('partial'):
                # Only print partial results occasionally to avoid spam
                if frame_count % 20 == 0:
                    print(f"partial: '{partial['partial']}'")
    
    try:
        # Stream audio continuously to Vosk
        with sd.InputStream(samplerate=16000, blocksize=1600, 
                           device=None, dtype='float32', channels=1, 
                           callback=audio_callback):
            print("Audio stream active - Vosk handling all VAD internally")
            while True:
                time.sleep(0.1)
                
    except KeyboardInterrupt:
        print(f"\nStopping... Captured {len(results)} utterances:")
        for i, result in enumerate(results, 1):
            print(f"  {i}. {result}")
        
        # Get any final result
        final = json.loads(recognizer.FinalResult())
        if final.get('text'):
            print(f"Final: {final['text']}")

if __name__ == "__main__":
    test_vosk_builtin_vad()