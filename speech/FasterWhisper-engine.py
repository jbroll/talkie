class WhisperAdapter(SpeechEngineAdapter):
    """Adapter for OpenAI Whisper (using faster-whisper)"""
    
    def __init__(self, model_path: str, samplerate: int = 16000, 
                 device: str = "cpu", compute_type: str = "int8"):
        super().__init__(model_path, samplerate)
        self.device = device
        self.compute_type = compute_type
        self.model = None
        self.audio_buffer = []
        self.buffer_duration = 5.0  # Process every 5 seconds
        
    def initialize(self) -> bool:
        try:
            from faster_whisper import WhisperModel
            self.model = WhisperModel(
                self.model_path, 
                device=self.device, 
                compute_type=self.compute_type
            )
            self.is_initialized = True
            return True
        except Exception as e:
            print(f"Failed to initialize Whisper: {e}")
            return False
            
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
            self.audio_buffer = self.audio_buffer[target_samples:]
            
            try:
                segments, _ = self.model.transcribe(audio_segment, language="en")
                text_parts = []
                for segment in segments:
                    text_parts.append(segment.text.strip())
                
                if text_parts:
                    return SpeechResult(
                        text=" ".join(text_parts),
                        is_final=True,
                        confidence=0.9  # Whisper doesn't provide confidence scores
                    )
            except Exception as e:
                print(f"Whisper transcription error: {e}")
                
        return None
        
    def reset(self):
        self.audio_buffer.clear()
        
    def cleanup(self):
        self.model = None
        self.audio_buffer.clear()
        self.is_initialized = False

