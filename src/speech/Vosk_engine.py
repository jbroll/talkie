import json
from typing import Optional
from .speech_engine import SpeechEngine, SpeechResult

class VoskAdapter(SpeechEngine):
    """Adapter for Vosk speech engine"""
    
    def __init__(self, model_path: str, samplerate: int = 16000, 
                 max_alternatives: int = 0, beam: int = 20, lattice_beam: int = 8,
                 confidence_threshold: float = 0.7):
        super().__init__(model_path, samplerate)
        self.model = None
        self.recognizer = None
        self.vosk = None  # Store vosk module reference
        
        # Vosk parameters
        self.max_alternatives = max_alternatives
        self.beam = beam
        self.lattice_beam = lattice_beam
        self.confidence_threshold = confidence_threshold
        
    def initialize(self) -> bool:
        try:
            import vosk
            self.vosk = vosk  # Store module reference for later use
            vosk.SetLogLevel(-1)
            self.model = vosk.Model(self.model_path)
            self.recognizer = vosk.KaldiRecognizer(self.model, self.samplerate)
            
            # Configure recognizer for better noise rejection
            self.recognizer.SetWords(True)
            
            # Try to set beam parameters for better noise rejection
            # Higher beam values = more selective, better noise rejection but slower
            try:
                self._apply_vosk_parameters()
            except Exception as e:
                print(f"Vosk: Some advanced parameters not available: {e}")
            
            self.is_initialized = True
            return True
        except Exception as e:
            print(f"Vosk initialization failed: {e}")
            return False
            
    def process_audio(self, audio_data: bytes) -> Optional[SpeechResult]:
        if not self.is_initialized:
            return None
            
        if self.recognizer.AcceptWaveform(audio_data):
            result = json.loads(self.recognizer.Result())
            
            # Extract text and confidence based on result format
            text = ""
            confidence = 0.0
            
            if 'alternatives' in result and result['alternatives']:
                # New format with alternatives (has confidence scores)
                best_alternative = result['alternatives'][0]
                text = best_alternative.get('text', '')
                confidence = best_alternative.get('confidence', 0.0)
            elif 'text' in result:
                # Old format without alternatives (no confidence)
                text = result['text']
                confidence = 0.0
                
            if text.strip():
                # Apply confidence filtering - only return results above threshold
                if confidence >= self.confidence_threshold:
                    return SpeechResult(
                        text=text,
                        is_final=True,
                        confidence=confidence
                    )
                else:
                    print(f"Vosk: Filtered low confidence result ({confidence:.2f} < {self.confidence_threshold:.2f}): '{text}'")
                    return None
        else:
            partial = json.loads(self.recognizer.PartialResult())
            if partial.get('partial'):
                return SpeechResult(
                    text=partial['partial'],
                    is_final=False
                )
        return None
        
    def reset(self):
        if self.recognizer and self.vosk:
            # Vosk doesn't have explicit reset, create new recognizer
            self.recognizer = self.vosk.KaldiRecognizer(self.model, self.samplerate)
            self.recognizer.SetWords(True)
            # Reapply parameters
            try:
                self._apply_vosk_parameters()
            except Exception as e:
                print(f"Vosk: Error reapplying parameters after reset: {e}")
            
    def get_final_result(self) -> Optional[SpeechResult]:
        """Get the final result from Vosk after all audio has been processed"""
        if not self.is_initialized or not self.recognizer:
            return None
            
        try:
            result = json.loads(self.recognizer.FinalResult())
            
            # Extract text and confidence based on result format
            text = ""
            confidence = 0.0
            
            if 'alternatives' in result and result['alternatives']:
                # New format with alternatives (has confidence scores)
                best_alternative = result['alternatives'][0]
                text = best_alternative.get('text', '')
                confidence = best_alternative.get('confidence', 0.0)
            elif 'text' in result:
                # Old format without alternatives (no confidence)
                text = result['text']
                confidence = 0.0
                
            if text.strip():
                return SpeechResult(
                    text=text,
                    is_final=True,
                    confidence=confidence
                )
        except Exception as e:
            pass
        return None
        
    def _apply_vosk_parameters(self):
        """Apply Vosk parameters to the recognizer"""
        if not self.recognizer:
            return
            
        # These methods might not exist in all Vosk versions
        if hasattr(self.recognizer, 'SetMaxAlternatives'):
            # Set to at least 1 to get confidence scores, or user's preference if higher
            alternatives_count = max(1, self.max_alternatives)
            self.recognizer.SetMaxAlternatives(alternatives_count)
            print(f"✓ Vosk: SetMaxAlternatives set to {alternatives_count} (for confidence scores)")
            
        # Look for beam configuration options
        if hasattr(self.recognizer, 'SetBeam'):
            self.recognizer.SetBeam(self.beam)
            print(f"✓ Vosk: Beam set to {self.beam} for noise rejection")
            
        if hasattr(self.recognizer, 'SetLatticeBeam'):
            self.recognizer.SetLatticeBeam(self.lattice_beam)
            print(f"✓ Vosk: Lattice beam set to {self.lattice_beam}")
    
    def update_max_alternatives(self, value: int):
        """Update max alternatives parameter"""
        self.max_alternatives = int(value)
        if self.recognizer and hasattr(self.recognizer, 'SetMaxAlternatives'):
            self.recognizer.SetMaxAlternatives(self.max_alternatives)
            print(f"✓ Vosk: Max alternatives updated to {self.max_alternatives}")
    
    def update_beam(self, value: int):
        """Update beam parameter"""
        self.beam = int(value)
        if self.recognizer and hasattr(self.recognizer, 'SetBeam'):
            self.recognizer.SetBeam(self.beam)
            print(f"✓ Vosk: Beam updated to {self.beam}")
    
    def update_lattice_beam(self, value: int):
        """Update lattice beam parameter"""
        self.lattice_beam = int(value)
        if self.recognizer and hasattr(self.recognizer, 'SetLatticeBeam'):
            self.recognizer.SetLatticeBeam(self.lattice_beam)
            print(f"✓ Vosk: Lattice beam updated to {self.lattice_beam}")
    
    def update_confidence_threshold(self, value: float):
        """Update confidence threshold for filtering"""
        self.confidence_threshold = float(value)
        print(f"✓ Vosk: Confidence threshold updated to {self.confidence_threshold:.2f}")
            
    def cleanup(self):
        self.model = None
        self.recognizer = None
        self.is_initialized = False


