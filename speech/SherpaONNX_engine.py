import numpy as np
from typing import Optional
from .speech_engine import SpeechEngine, SpeechResult

class SherpaONNXAdapter(SpeechEngine):
    """Adapter for sherpa-onnx speech engine - CPU only"""
    
    def __init__(self, model_path: str, samplerate: int = 16000, 
                 use_int8: bool = True, **kwargs):
        super().__init__(model_path, samplerate)
        self.use_int8 = use_int8
        self.recognizer = None
        self.stream = None
        
    def initialize(self) -> bool:
        try:
            import sherpa_onnx
            
            # Configure the recognizer
            tokens = f"{self.model_path}/tokens.txt"
            
            if self.use_int8:
                # Use quantized INT8 models for better performance
                encoder = f"{self.model_path}/encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx"
                decoder = f"{self.model_path}/decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx" 
                joiner = f"{self.model_path}/joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx"
            else:
                # Use full precision FP32 models
                encoder = f"{self.model_path}/encoder-epoch-99-avg-1-chunk-16-left-128.onnx"
                decoder = f"{self.model_path}/decoder-epoch-99-avg-1-chunk-16-left-128.onnx" 
                joiner = f"{self.model_path}/joiner-epoch-99-avg-1-chunk-16-left-128.onnx"
            
            # Create recognizer using CPU provider
            self.recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
                tokens=tokens,
                encoder=encoder,
                decoder=decoder,
                joiner=joiner,
                num_threads=2,
                sample_rate=self.samplerate,
                enable_endpoint_detection=False,  # Disabled for continuous streaming
                decoding_method="greedy_search",
                max_active_paths=4,
                provider="cpu"
            )
            
            # Create stream
            self.stream = self.recognizer.create_stream()
            
            self.is_initialized = True
            print(f"Sherpa-ONNX initialized with {'INT8' if self.use_int8 else 'FP32'} models using CPU")
            return True
            
        except Exception as e:
            print(f"Failed to initialize Sherpa-ONNX: {e}")
            import traceback
            traceback.print_exc()
            return False
            
    def process_audio(self, audio_data: bytes) -> Optional[SpeechResult]:
        if not self.is_initialized:
            return None
            
        try:
            # Convert bytes to numpy array of floats
            # Assuming 16-bit PCM audio data - match Vosk's format exactly
            audio_np = np.frombuffer(audio_data, dtype=np.int16).astype(np.float32) / 32768.0
            
            # Ensure proper sample rate and format for sherpa-onnx
            # sherpa-onnx expects float32 samples normalized to [-1, 1]
            self.stream.accept_waveform(self.samplerate, audio_np)
            
            # Always decode what we have so far
            if self.recognizer.is_ready(self.stream):
                self.recognizer.decode_stream(self.stream)
                
            # Get current result (always partial since endpoint detection is disabled)
            text = self.recognizer.get_result(self.stream).strip()
            
            # Return partial result if we have text
            # Since endpoint detection is disabled, we rely on external silence detection
            if text:
                return SpeechResult(
                    text=text,
                    is_final=False,  # Always partial when endpoint detection is disabled
                    confidence=0.8   # Good confidence for streaming results
                )
                    
        except Exception as e:
            print(f"Error processing audio with Sherpa-ONNX: {e}")
            import traceback
            traceback.print_exc()
            
        return None
        
    def reset(self):
        if self.stream and self.recognizer:
            self.recognizer.reset(self.stream)
            
    def get_final_result(self) -> Optional[SpeechResult]:
        """Get the final result from Sherpa-ONNX after all audio has been processed"""
        if not self.is_initialized or not self.recognizer or not self.stream:
            return None
            
        try:
            # Force endpoint detection and get final result
            if self.recognizer.is_ready(self.stream):
                self.recognizer.decode_stream(self.stream)
                
            # Get the current text as final result
            text = self.recognizer.get_result(self.stream).strip()
            
            if text:
                # Reset the stream after getting final result
                self.recognizer.reset(self.stream)
                return SpeechResult(
                    text=text,
                    is_final=True,
                    confidence=0.9
                )
        except Exception as e:
            print(f"Error getting Sherpa-ONNX final result: {e}")
            import traceback
            traceback.print_exc()
        return None
        
    def cleanup(self):
        self.stream = None
        self.recognizer = None
        self.is_initialized = False