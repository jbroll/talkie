# @npu_whisper_adapter
class OpenVINOWhisperAdapter(SpeechEngineAdapter):
    """Adapter for Whisper using OpenVINO with NPU support"""
    
    def __init__(self, model_path: str, samplerate: int = 16000, 
                 device: str = "AUTO", precision: str = "FP16"):
        super().__init__(model_path, samplerate)
        self.device = device  # Can be "NPU", "CPU", "GPU", "AUTO"
        self.precision = precision
        self.pipeline = None
        self.audio_buffer = []
        self.buffer_duration = 3.0  # Process every 3 seconds for better NPU efficiency
        
    def initialize(self) -> bool:
        try:
            # Check if NPU is available
            available_devices = self._get_available_devices()
            if self.device == "NPU" and "NPU" not in available_devices:
                logger.warning("NPU not available, falling back to CPU")
                self.device = "CPU"
            elif self.device == "AUTO":
                # Prefer NPU if available, then GPU, then CPU
                if "NPU" in available_devices:
                    self.device = "NPU"
                elif "GPU" in available_devices:
                    self.device = "GPU"
                else:
                    self.device = "CPU"
                    
            logger.info(f"Initializing OpenVINO Whisper on device: {self.device}")
            
            # Use OpenVINO GenAI for Whisper
            import openvino_genai as ov_genai
            
            # Convert model if needed
            model_path = self._ensure_openvino_model()
            
            self.pipeline = ov_genai.WhisperPipeline(
                str(model_path), 
                device=self.device
            )
            
            self.is_initialized = True
            logger.info(f"OpenVINO Whisper initialized successfully on {self.device}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize OpenVINO Whisper: {e}")
            return False
            
    def _get_available_devices(self):
        """Get list of available OpenVINO devices"""
        try:
            import openvino as ov
            core = ov.Core()
            return core.available_devices
        except:
            return ["CPU"]
            
    def _ensure_openvino_model(self):
        """Convert model to OpenVINO format if needed"""
        from pathlib import Path
        
        model_dir = Path(self.model_path)
        if model_dir.is_dir() and (model_dir / "openvino_model.xml").exists():
            # Already converted
            return model_dir
            
        # Convert using optimum-cli
        import subprocess
        import tempfile
        
        output_dir = Path(tempfile.gettempdir()) / f"whisper_ov_{self.model_path.replace('/', '_')}"
        if not output_dir.exists():
            try:
                cmd = [
                    "optimum-cli", "export", "openvino",
                    "--model", self.model_path,
                    "--task", "automatic-speech-recognition-with-past",
                    str(output_dir)
                ]
                subprocess.run(cmd, check=True, capture_output=True)
                logger.info(f"Model converted to OpenVINO format: {output_dir}")
            except subprocess.CalledProcessError as e:
                logger.error(f"Model conversion failed: {e}")
                raise
                
        return output_dir
        
    def process_audio(self, audio_data: bytes) -> Optional[SpeechResult]:
        if not self.is_initialized:
            return None
            
        # Convert bytes to numpy array and accumulate
        import numpy as np
        audio_np = np.frombuffer(audio_data, dtype=np.int16).astype(np.float32) / 32768.0
        self.audio_buffer.extend(audio_np)
        
        # Process when buffer reaches target duration
        target_samples = int(self.buffer_duration * self.samplerate)
        if len(self.audio_buffer) >= target_samples:
            audio_segment = np.array(self.audio_buffer[:target_samples])
            self.audio_buffer = self.audio_buffer[target_samples//2:]  # 50% overlap
            
            try:
                # Use OpenVINO GenAI pipeline
                result = self.pipeline.generate(audio_segment)
                
                if result and result.texts:
                    text = result.texts[0].strip()
                    if text:
                        return SpeechResult(
                            text=text,
                            is_final=True,
                            confidence=0.9  # OpenVINO doesn't provide confidence scores
                        )
                        
            except Exception as e:
                logger.error(f"OpenVINO Whisper transcription error: {e}")
                
        return None
        
    def reset(self):
        self.audio_buffer.clear()
        
    def cleanup(self):
        if self.pipeline:
            del self.pipeline
        self.pipeline = None
        self.audio_buffer.clear()
        self.is_initialized = False

# @npu_factory_update
class NPUEnabledSpeechEngineFactory(SpeechEngineFactory):
    """Extended factory with NPU support"""
    
    _adapters = {
        SpeechEngineType.VOSK: VoskAdapter,
        SpeechEngineType.FASTER_WHISPER: WhisperAdapter,
        SpeechEngineType.OPENVINO_WHISPER: OpenVINOWhisperAdapter,
        # Add more engines as needed
    }
    
    @classmethod
    def create_npu_adapter(cls, model_path: str, **kwargs) -> OpenVINOWhisperAdapter:
        """Create NPU-optimized Whisper adapter"""
        return OpenVINOWhisperAdapter(
            model_path=model_path,
            device="NPU",
            **kwargs
        )
    
    @classmethod
    def get_best_device_adapter(cls, model_path: str, **kwargs) -> OpenVINOWhisperAdapter:
        """Automatically select best available device"""
        return OpenVINOWhisperAdapter(
            model_path=model_path,
            device="AUTO",
            **kwargs
        )

# @device_detection
def detect_intel_npu():
    """Detect if Intel NPU is available"""
    try:
        import openvino as ov
        core = ov.Core()
        devices = core.available_devices
        
        npu_devices = [d for d in devices if "NPU" in d]
        if npu_devices:
            logger.info(f"Intel NPU detected: {npu_devices}")
            return True
        else:
            logger.info("No Intel NPU detected")
            return False
            
    except ImportError:
        logger.warning("OpenVINO not available - cannot detect NPU")
        return False
    except Exception as e:
        logger.error(f"Error detecting NPU: {e}")
        return False

# @requirements_check
def check_npu_requirements():
    """Check if NPU requirements are met"""
    requirements = {
        "openvino": False,
        "openvino-genai": False,
        "optimum": False,
        "npu_device": False
    }
    
    try:
        import openvino
        requirements["openvino"] = True
    except ImportError:
        pass
        
    try:
        import openvino_genai
        requirements["openvino-genai"] = True
    except ImportError:
        pass
        
    try:
        import optimum
        requirements["optimum"] = True
    except ImportError:
        pass
        
    requirements["npu_device"] = detect_intel_npu()
    
    return requirements

# @usage_example_npu
def example_npu_usage():
    """Example of using NPU-enabled speech recognition"""
    
    # Check requirements
    reqs = check_npu_requirements()
    if not all(reqs.values()):
        missing = [k for k, v in reqs.items() if not v]
        logger.warning(f"Missing NPU requirements: {missing}")
        
    def handle_result(result: SpeechResult):
        print(f"{'Final' if result.is_final else 'Partial'}: {result.text}")
        
    # Try NPU first, fallback to CPU
    try:
        manager = SpeechManager(
            engine_type=SpeechEngineType.OPENVINO_WHISPER,
            model_path="openai/whisper-base",  # Will be auto-converted
            result_callback=handle_result,
            device="AUTO",  # Auto-select best device
            samplerate=16000
        )
        
        if manager.initialize():
            logger.info("NPU/OpenVINO speech manager initialized successfully")
            manager.start()
            # manager.add_audio(audio_data)
            manager.cleanup()
        else:
            logger.error("Failed to initialize NPU speech manager")
            
    except Exception as e:
        logger.error(f"NPU usage example failed: {e}")
