import numpy as np
from typing import Optional
from .speech_engine import SpeechEngine, SpeechResult

class SherpaONNXAdapter(SpeechEngine):
    """Adapter for sherpa-onnx speech engine"""
    
    def __init__(self, model_path: str, samplerate: int = 16000, 
                 use_int8: bool = True, **kwargs):
        super().__init__(model_path, samplerate)
        self.use_int8 = use_int8
        self.recognizer = None
        self.stream = None
        self.config = None
        
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
            
            # Create recognizer using class method
            self.recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
                tokens=tokens,
                encoder=encoder,
                decoder=decoder,
                joiner=joiner,
                num_threads=2,
                sample_rate=self.samplerate,  # Use int, not float
                enable_endpoint_detection=True,
                rule1_min_trailing_silence=2.4,
                rule2_min_trailing_silence=1.2,
                rule3_min_utterance_length=20.0,
                decoding_method="greedy_search",
                max_active_paths=4,
                provider="cpu"
            )
            
            # Create stream
            self.stream = self.recognizer.create_stream()
            
            self.is_initialized = True
            print(f"Sherpa-ONNX initialized with {'INT8' if self.use_int8 else 'FP32'} models")
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
            # Assuming 16-bit PCM audio data
            audio_np = np.frombuffer(audio_data, dtype=np.int16).astype(np.float32) / 32768.0
            
            # Feed audio to the stream
            self.stream.accept_waveform(self.samplerate, audio_np)
            
            # Check for results
            text_changed = False
            
            # Check if we have a partial result
            if self.recognizer.is_ready(self.stream):
                self.recognizer.decode_stream(self.stream)
                
            # Get current partial result (get_result returns a string directly)
            text = self.recognizer.get_result(self.stream).strip()
            
            # Check if endpoint is detected (final result)
            if self.recognizer.is_endpoint(self.stream):
                # Final result
                if text:
                    result = SpeechResult(
                        text=text,
                        is_final=True,
                        confidence=0.9  # sherpa-onnx doesn't provide confidence scores
                    )
                    # Reset for next utterance
                    self.recognizer.reset(self.stream)
                    return result
            else:
                # Partial result
                if text:
                    return SpeechResult(
                        text=text,
                        is_final=False,
                        confidence=0.5
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
        self.config = None
        self.is_initialized = False