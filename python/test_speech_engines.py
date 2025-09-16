#!/home/john/src/talkie/bin/python3
"""
Automated test script for speech recognition engines
Tests both Vosk and OpenVINO engines with real audio files
"""

import sys
import os
import wave
import numpy as np
import logging
import argparse
from pathlib import Path

# Add the speech module to the path
sys.path.append(str(Path(__file__).parent))

from speech.speech_engine import SpeechManager, SpeechEngineType, SpeechResult
from speech.Vosk_engine import VoskAdapter
from speech.SherpaONNX_engine import SherpaONNXAdapter

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class SpeechEngineTestRunner:
    """Test runner for speech recognition engines"""
    
    def __init__(self):
        self.results = []
        
    def load_wav_file(self, wav_path):
        """Load WAV file and return audio data and sample rate"""
        try:
            with wave.open(wav_path, 'rb') as wav_file:
                sample_rate = wav_file.getframerate()
                n_channels = wav_file.getnchannels()
                n_frames = wav_file.getnframes()
                audio_data = wav_file.readframes(n_frames)
                
                # Convert to numpy array
                if wav_file.getsampwidth() == 2:  # 16-bit
                    audio_np = np.frombuffer(audio_data, dtype=np.int16)
                else:
                    raise ValueError(f"Unsupported bit depth: {wav_file.getsampwidth()}")
                
                if n_channels == 2:  # Convert stereo to mono
                    audio_np = audio_np.reshape(-1, 2).mean(axis=1).astype(np.int16)
                
                logger.info(f"Loaded {wav_path}: {len(audio_np)} samples, {sample_rate}Hz, {n_channels} channel(s)")
                return audio_np, sample_rate
                
        except Exception as e:
            logger.error(f"Error loading WAV file {wav_path}: {e}")
            return None, None
    
    def chunk_audio(self, audio_np, sample_rate, chunk_duration=0.1):
        """Split audio into chunks like the main application does"""
        chunk_size = int(sample_rate * chunk_duration)
        chunks = []
        
        for i in range(0, len(audio_np), chunk_size):
            chunk = audio_np[i:i + chunk_size]
            if len(chunk) == chunk_size:  # Only use full chunks
                chunks.append(chunk.tobytes())
        
        logger.info(f"Split audio into {len(chunks)} chunks of {chunk_duration}s each")
        return chunks
    
    def test_engine(self, engine_type, model_path, sample_rate, audio_chunks, **kwargs):
        """Test a specific speech engine with audio chunks"""
        logger.info(f"Testing {engine_type.value} engine...")
        
        transcription_results = []
        
        def collect_result(result: SpeechResult):
            transcription_results.append(result)
            logger.info(f"[{engine_type.value}] {'Final' if result.is_final else 'Partial'}: '{result.text}'")
        
        try:
            # Create speech manager
            manager = SpeechManager(
                engine_type=engine_type,
                model_path=model_path,
                result_callback=collect_result,
                samplerate=sample_rate,
                **kwargs
            )
            
            if not manager.initialize():
                logger.error(f"Failed to initialize {engine_type.value} engine")
                return None
            
            # Process audio chunks directly (like our fixed version)
            for i, chunk in enumerate(audio_chunks):
                result = manager.adapter.process_audio(chunk)
                if result:
                    collect_result(result)
                
                # Show progress
                if i % 50 == 0:
                    logger.info(f"Processed {i}/{len(audio_chunks)} chunks...")
            
            # Get final result if adapter supports it (important for Vosk)
            final_result = manager.adapter.get_final_result()
            if final_result:
                collect_result(final_result)
                logger.info(f"[{engine_type.value}] Got final result: '{final_result.text}'")
            
            # Cleanup
            manager.cleanup()
            
            # Combine final results
            final_texts = [r.text for r in transcription_results if r.is_final]
            full_transcription = " ".join(final_texts)
            
            logger.info(f"[{engine_type.value}] Final transcription: '{full_transcription}'")
            return {
                'engine': engine_type.value,
                'transcription': full_transcription,
                'results': transcription_results
            }
            
        except Exception as e:
            logger.error(f"Error testing {engine_type.value}: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return None

def main():
    parser = argparse.ArgumentParser(description='Test speech recognition engines')
    parser.add_argument('audio_file', help='Path to WAV audio file')
    parser.add_argument('--vosk-model', default='/home/john/Downloads/vosk-model-en-us-0.22-lgraph',
                       help='Path to Vosk model')
    parser.add_argument('--sherpa-model', default='models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26',
                       help='Path to Sherpa-ONNX model directory')
    parser.add_argument('--test-vosk', action='store_true', help='Test Vosk engine')
    parser.add_argument('--test-sherpa', action='store_true', help='Test Sherpa-ONNX engine')
    parser.add_argument('--verbose', action='store_true', help='Enable debug logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    if not (args.test_vosk or args.test_sherpa):
        args.test_sherpa = True  # Default to sherpa-onnx for streaming
    
    # Initialize test runner
    runner = SpeechEngineTestRunner()
    
    # Load audio file
    audio_np, sample_rate = runner.load_wav_file(args.audio_file)
    if audio_np is None:
        logger.error("Failed to load audio file")
        return 1
    
    # Chunk audio
    chunks = runner.chunk_audio(audio_np, sample_rate)
    if not chunks:
        logger.error("No audio chunks created")
        return 1
    
    # Test engines
    results = []
    
    if args.test_vosk:
        if os.path.exists(args.vosk_model):
            vosk_result = runner.test_engine(
                SpeechEngineType.VOSK,
                args.vosk_model,
                sample_rate,
                chunks
            )
            if vosk_result:
                results.append(vosk_result)
        else:
            logger.error(f"Vosk model not found: {args.vosk_model}")
    
    if args.test_sherpa:
        if os.path.exists(args.sherpa_model):
            sherpa_result = runner.test_engine(
                SpeechEngineType.SHERPA_ONNX,
                args.sherpa_model,
                sample_rate,
                chunks,
                use_int8=True
            )
            if sherpa_result:
                results.append(sherpa_result)
        else:
            logger.error(f"Sherpa-ONNX model not found: {args.sherpa_model}")
    
    # Print comparison
    print("\n" + "="*60)
    print("TRANSCRIPTION RESULTS COMPARISON")
    print("="*60)
    
    for result in results:
        print(f"\n{result['engine'].upper()}:")
        print(f"  Transcription: '{result['transcription']}'")
        print(f"  Word count: {len(result['transcription'].split())}")
        print(f"  Results count: {len(result['results'])}")
    
    print("\n" + "="*60)
    
    return 0

if __name__ == '__main__':
    sys.exit(main())