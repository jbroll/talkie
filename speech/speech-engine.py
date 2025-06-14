# @imports
import abc
import json
import queue
import threading
from typing import Dict, Any, Optional, Callable
from enum import Enum

# @base_adapter
class SpeechEngineType(Enum):
    VOSK = "vosk"
    WHISPER = "whisper"
    FASTER_WHISPER = "faster_whisper"
    DISTIL_WHISPER = "distil_whisper"
    SPEECHBRAIN = "speechbrain"

class SpeechResult:
    """Standardized result format for all engines"""
    def __init__(self, text: str, is_final: bool, confidence: float = 0.0, 
                 word_timings: Optional[list] = None):
        self.text = text
        self.is_final = is_final
        self.confidence = confidence
        self.word_timings = word_timings or []

class SpeechEngine(abc.ABC):
    """Base adapter interface for speech recognition engines"""
    
    def __init__(self, model_path: str, samplerate: int = 16000):
        self.model_path = model_path
        self.samplerate = samplerate
        self.is_initialized = False
        
    @abc.abstractmethod
    def initialize(self) -> bool:
        """Initialize the speech engine"""
        pass
        
    @abc.abstractmethod
    def process_audio(self, audio_data: bytes) -> Optional[SpeechResult]:
        """Process audio chunk and return result if available"""
        pass
        
    @abc.abstractmethod
    def reset(self):
        """Reset the recognition state"""
        pass
        
    @abc.abstractmethod
    def cleanup(self):
        """Clean up resources"""
        pass

# @engine_factory
class SpeechEngineFactory:
    """Factory for creating speech engine adapters"""
    
    _adapters = {
        SpeechEngineType.VOSK: VoskAdapter,
        SpeechEngineType.FASTER_WHISPER: WhisperAdapter,
        # Add more engines as needed
    }
    
    @classmethod
    def create_adapter(cls, engine_type: SpeechEngineType, 
                      model_path: str, **kwargs) -> SpeechEngineAdapter:
        """Create a speech engine adapter"""
        if engine_type not in cls._adapters:
            raise ValueError(f"Unsupported engine type: {engine_type}")
            
        adapter_class = cls._adapters[engine_type]
        return adapter_class(model_path, **kwargs)
    
    @classmethod
    def register_adapter(cls, engine_type: SpeechEngineType, 
                        adapter_class: type):
        """Register a new adapter type"""
        cls._adapters[engine_type] = adapter_class

# @speech_manager
class SpeechManager:
    """High-level manager for speech recognition with pluggable engines"""
    
    def __init__(self, engine_type: SpeechEngineType, model_path: str, 
                 result_callback: Callable[[SpeechResult], None], **kwargs):
        self.engine_type = engine_type
        self.model_path = model_path
        self.result_callback = result_callback
        self.adapter = None
        self.audio_queue = queue.Queue()
        self.running = False
        self.thread = None
        self.kwargs = kwargs
        
    def initialize(self) -> bool:
        """Initialize the speech manager"""
        try:
            self.adapter = SpeechEngineFactory.create_adapter(
                self.engine_type, self.model_path, **self.kwargs
            )
            return self.adapter.initialize()
        except Exception as e:
            print(f"Failed to initialize speech manager: {e}")
            return False
            
    def start(self):
        """Start processing audio"""
        if not self.adapter or not self.adapter.is_initialized:
            raise RuntimeError("Speech manager not initialized")
            
        self.running = True
        self.thread = threading.Thread(target=self._process_loop)
        self.thread.start()
        
    def stop(self):
        """Stop processing audio"""
        self.running = False
        if self.thread:
            self.thread.join()
            
    def add_audio(self, audio_data: bytes):
        """Add audio data to processing queue"""
        if self.running:
            self.audio_queue.put(audio_data)
            
    def _process_loop(self):
        """Main processing loop"""
        while self.running:
            try:
                audio_data = self.audio_queue.get(timeout=0.1)
                result = self.adapter.process_audio(audio_data)
                if result:
                    self.result_callback(result)
            except queue.Empty:
                continue
            except Exception as e:
                print(f"Error in speech processing: {e}")
                
    def switch_engine(self, new_engine_type: SpeechEngineType, 
                     new_model_path: str, **kwargs):
        """Switch to a different speech engine"""
        was_running = self.running
        if was_running:
            self.stop()
            
        if self.adapter:
            self.adapter.cleanup()
            
        self.engine_type = new_engine_type
        self.model_path = new_model_path
        self.kwargs = kwargs
        
        if self.initialize() and was_running:
            self.start()
            
    def cleanup(self):
        """Clean up resources"""
        self.stop()
        if self.adapter:
            self.adapter.cleanup()

# @usage_example
def example_usage():
    """Example of how to use the speech engine adapter"""
    
    def handle_result(result: SpeechResult):
        print(f"{'Final' if result.is_final else 'Partial'}: {result.text}")
        
    # Create speech manager with Vosk
    manager = SpeechManager(
        engine_type=SpeechEngineType.VOSK,
        model_path="/path/to/vosk/model",
        result_callback=handle_result,
        samplerate=16000
    )
    
    if manager.initialize():
        manager.start()
        
        # Simulate audio processing
        # manager.add_audio(audio_data)
        
        # Switch to Whisper
        manager.switch_engine(
            SpeechEngineType.FASTER_WHISPER,
            "base.en",  # or path to local model
            device="cpu",
            compute_type="int8"
        )
        
        manager.cleanup()
