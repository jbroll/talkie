import numpy as np
from typing import Optional
from .speech_engine import SpeechEngine, SpeechResult

class SherpaONNXAdapter(SpeechEngine):
    """Adapter for sherpa-onnx speech engine"""
    
    def __init__(self, model_path: str, samplerate: int = 16000, 
                 use_int8: bool = True, provider: str = "auto", **kwargs):
        super().__init__(model_path, samplerate)
        self.use_int8 = use_int8
        self.provider = provider
        self.recognizer = None
        self.stream = None
        self.config = None
        
    def _openvino_available(self) -> bool:
        """Check if OpenVINO execution provider is available"""
        try:
            import onnxruntime as ort
            available_providers = ort.get_available_providers()
            openvino_available = 'OpenVINOExecutionProvider' in available_providers
            
            if openvino_available:
                # Also check if we have OpenVINO GPU device available
                try:
                    import openvino as ov
                    core = ov.Core()
                    devices = core.available_devices
                    gpu_available = 'GPU' in devices
                    if gpu_available:
                        print("OpenVINO GPU device detected")
                        return True
                    else:
                        print("OpenVINO available but no GPU device found")
                        return False
                except Exception as e:
                    print(f"OpenVINO import failed: {e}")
                    return False
            else:
                print("OpenVINO execution provider not available")
                return False
        except Exception as e:
            print(f"Failed to check OpenVINO availability: {e}")
            return False
    
    def _select_provider(self) -> str:
        """Select the best available provider based on user preference and hardware"""
        if self.provider == "cpu":
            return "cpu"
        elif self.provider == "openvino-gpu":
            # Use OpenVINO GPU provider
            if self._openvino_available():
                print("Using OpenVINO GPU provider for sherpa-onnx")
                return "openvino"
            else:
                print("OpenVINO GPU not available, falling back to CPU")
                return "cpu"
        elif self.provider == "gpu":
            # Try OpenVINO GPU first, then CUDA, then CPU
            if self._openvino_available():
                print("Using OpenVINO GPU provider for sherpa-onnx")
                return "openvino"
            else:
                try:
                    import torch
                    if torch.cuda.is_available():
                        print("Using CUDA GPU provider for sherpa-onnx")
                        return "cuda"
                    else:
                        print("No GPU available, using CPU for sherpa-onnx")
                        return "cpu"
                except:
                    print("PyTorch not available, using CPU for sherpa-onnx") 
                    return "cpu"
        elif self.provider == "npu":
            # NPU not supported by sherpa-onnx, fallback to best available
            print("NPU not supported by sherpa-onnx, falling back to GPU")
            return self._select_provider_fallback("gpu")
        elif self.provider == "auto":
            # Auto-detect best available provider: OpenVINO GPU -> CUDA -> CPU
            if self._openvino_available():
                print("Auto-detected OpenVINO GPU for sherpa-onnx")
                return "openvino"
            else:
                try:
                    import torch
                    if torch.cuda.is_available():
                        print("Auto-detected CUDA GPU for sherpa-onnx")
                        return "cuda"
                    else:
                        print("Auto-detected CPU for sherpa-onnx (no GPU available)")
                        return "cpu"
                except:
                    print("PyTorch not available, using CPU for sherpa-onnx")
                    return "cpu"
        else:
            print(f"Unknown provider '{self.provider}', using CPU")
            return "cpu"
            
    def _select_provider_fallback(self, fallback_provider: str) -> str:
        """Helper method for fallback provider selection"""
        original_provider = self.provider
        self.provider = fallback_provider
        result = self._select_provider()
        self.provider = original_provider
        return result
        
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
            
            # Determine the provider to use
            actual_provider = self._select_provider()
            
            # Configure environment for OpenVINO if selected
            if actual_provider == "openvino":
                # Set ONNX Runtime to use OpenVINO execution provider
                import os
                os.environ['ORT_PROVIDERS'] = 'OpenVINOExecutionProvider,CPUExecutionProvider'
                # Use fewer threads for GPU processing
                num_threads = 1
                # For sherpa-onnx, we pass "cuda" which it will map to available providers including OpenVINO
                provider_name = "cuda"
            else:
                num_threads = 2
                provider_name = actual_provider
                
            # Create recognizer using class method
            # Disable endpoint detection for streaming speech recognition
            # This prevents cutting off words mid-sentence 
            self.recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
                tokens=tokens,
                encoder=encoder,
                decoder=decoder,
                joiner=joiner,
                num_threads=num_threads,
                sample_rate=self.samplerate,  # Use int, not float
                enable_endpoint_detection=False,  # Disabled for continuous streaming
                decoding_method="greedy_search",
                max_active_paths=4,
                provider=provider_name
            )
            
            # Create stream
            self.stream = self.recognizer.create_stream()
            
            self.is_initialized = True
            print(f"Sherpa-ONNX initialized with {'INT8' if self.use_int8 else 'FP32'} models using {actual_provider.upper()} provider")
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
        self.config = None
        self.is_initialized = False