#!/usr/bin/env python3
import sys
import logging
import time
import numpy as np
from pathlib import Path

# Add the speech module to path
sys.path.insert(0, str(Path(__file__).parent))

from speech.speech_engine import SpeechManager, SpeechEngineType, SpeechResult

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def test_engine(engine_type: SpeechEngineType, **kwargs):
    """Test specific speech engine with synthetic audio"""
    print(f"\n{'='*60}")
    print(f"Testing {engine_type.value}...")
    print(f"Parameters: {kwargs}")
    print('='*60)
    
    results = []
    
    def collect_result(result: SpeechResult):
        results.append(result)
        final_str = "FINAL" if result.is_final else "PARTIAL"
        print(f"[{final_str}] {result.text} (confidence: {result.confidence:.2f})")
    
    try:
        # Create speech manager
        manager = SpeechManager(
            engine_type=engine_type,
            result_callback=collect_result,
            **kwargs
        )
        
        print(f"Initializing {engine_type.value} engine...")
        if not manager.initialize():
            print(f"✗ Failed to initialize {engine_type.value}")
            return False
        
        print(f"✓ {engine_type.value} initialized successfully")
        
        # Start processing
        manager.start()
        print("Started audio processing...")
        
        # Generate test audio (3 seconds of 440Hz sine wave)
        samplerate = kwargs.get('samplerate', 16000)
        duration = 3.0
        print(f"Generating {duration}s test audio at {samplerate}Hz...")
        
        t = np.linspace(0, duration, int(samplerate * duration), False)
        audio_signal = np.sin(2 * np.pi * 440 * t)  # 440Hz A note
        audio_bytes = (audio_signal * 32767).astype(np.int16).tobytes()
        
        # Send audio data
        print("Sending audio data to engine...")
        manager.add_audio(audio_bytes)
        
        # Wait for processing
        print("Waiting for processing...")
        time.sleep(5)
        
        # Cleanup
        manager.cleanup()
        
        # Evaluate results
        success = len(results) > 0
        final_results = [r for r in results if r.is_final]
        
        print(f"\nResults Summary:")
        print(f"  Total results: {len(results)}")
        print(f"  Final results: {len(final_results)}")
        print(f"  Success: {'✓' if success else '✗'}")
        
        return success
        
    except Exception as e:
        print(f"✗ Error testing {engine_type.value}: {e}")
        logger.exception(f"Exception in {engine_type.value} test")
        return False

def main():
    print("Talkie Speech Engine Test Suite")
    print("="*60)
    
    test_results = {}
    
    # Test OpenVINO Whisper if possible
    print("\n1. Testing OpenVINO Whisper...")
    try:
        success_ov = test_engine(
            SpeechEngineType.OPENVINO_WHISPER,
            model_path="openai/whisper-base",
            device="AUTO",
            samplerate=16000
        )
        test_results['OpenVINO Whisper'] = success_ov
    except Exception as e:
        print(f"✗ OpenVINO Whisper test failed: {e}")
        test_results['OpenVINO Whisper'] = False
    
    # Test Vosk fallback
    print("\n\n2. Testing Vosk...")
    vosk_model_path = "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
    try:
        success_vosk = test_engine(
            SpeechEngineType.VOSK,
            model_path=vosk_model_path,
            samplerate=16000
        )
        test_results['Vosk'] = success_vosk
    except Exception as e:
        print(f"✗ Vosk test failed: {e}")
        test_results['Vosk'] = False
    
    # Final Summary
    print("\n" + "="*60)
    print("TEST SUMMARY")
    print("="*60)
    
    all_passed = True
    for engine, passed in test_results.items():
        status = "PASS" if passed else "FAIL"
        symbol = "✓" if passed else "✗"
        print(f"{symbol} {engine}: {status}")
        if not passed:
            all_passed = False
    
    print("="*60)
    if all_passed:
        print("🎉 All tests passed!")
        return 0
    else:
        print("❌ Some tests failed. Check logs for details.")
        return 1

if __name__ == "__main__":
    sys.exit(main())