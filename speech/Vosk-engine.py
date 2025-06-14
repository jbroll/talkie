class VoskAdapter(SpeechEngineAdapter):
    """Adapter for Vosk speech engine"""
    
    def __init__(self, model_path: str, samplerate: int = 16000):
        super().__init__(model_path, samplerate)
        self.model = None
        self.recognizer = None
        
    def initialize(self) -> bool:
        try:
            import vosk
            vosk.SetLogLevel(-1)
            self.model = vosk.Model(self.model_path)
            self.recognizer = vosk.KaldiRecognizer(self.model, self.samplerate)
            self.recognizer.SetWords(True)
            self.is_initialized = True
            return True
        except Exception as e:
            print(f"Failed to initialize Vosk: {e}")
            return False
            
    def process_audio(self, audio_data: bytes) -> Optional[SpeechResult]:
        if not self.is_initialized:
            return None
            
        if self.recognizer.AcceptWaveform(audio_data):
            result = json.loads(self.recognizer.Result())
            if result.get('text'):
                return SpeechResult(
                    text=result['text'],
                    is_final=True,
                    confidence=result.get('confidence', 0.0)
                )
        else:
            partial = json.loads(self.recognizer.PartialResult())
            if partial.get('partial'):
                return SpeechResult(
                    text=partial['partial'],
                    is_final=False
                )
        return None
        
    def reset(self):
        if self.recognizer:
            # Vosk doesn't have explicit reset, create new recognizer
            self.recognizer = vosk.KaldiRecognizer(self.model, self.samplerate)
            self.recognizer.SetWords(True)
            
    def cleanup(self):
        self.model = None
        self.recognizer = None
        self.is_initialized = False


