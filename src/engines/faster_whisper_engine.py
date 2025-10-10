#!/usr/bin/env python3
"""
Faster-Whisper Speech Engine - Coprocess Implementation

Inherits from SpeechEngineBase for common functionality.
Implements Whisper-specific model loading and transcription.
"""

import sys
import numpy as np
from faster_whisper import WhisperModel
from speech_engine_base import SpeechEngineBase


class FasterWhisperEngine(SpeechEngineBase):
    """Faster-Whisper implementation of speech recognition engine"""

    def __init__(self, model_path, sample_rate):
        # Initialize base class
        super().__init__(model_path, sample_rate, "faster-whisper", "1.0")

    def load_model(self, model_path):
        """Load Whisper model"""
        try:
            self.model = WhisperModel(
                model_path,
                device="cpu",
                compute_type="int8"
            )
            print(f"✓ Faster-Whisper model loaded: {model_path}", file=sys.stderr)
            return True
        except Exception as e:
            print(f"ERROR: Failed to load model: {e}", file=sys.stderr)
            return False

    def transcribe_audio(self, audio):
        """Transcribe audio using Faster-Whisper

        Args:
            audio: numpy float32 array at 16kHz

        Returns:
            tuple: (text, confidence) in Vosk-compatible format
        """
        # Transcribe with faster-whisper
        segments, info = self.model.transcribe(
            audio,
            beam_size=5,
            language="en",
            vad_filter=False  # We do our own VAD
        )

        # Collect all segments
        texts = []
        confidences = []
        logprobs = []

        for segment in segments:
            texts.append(segment.text.strip())
            logprobs.append(segment.avg_logprob)

            # Convert avg_logprob to Vosk-style confidence (0-1000 range)
            # avg_logprob typically ranges from -2.0 (bad) to -0.1 (good)
            # Map to 0-1000 range: -0.5 or better = high confidence (800+)
            logprob = segment.avg_logprob
            if logprob >= -0.5:
                conf = 900 + logprob * 200  # -0.5 to 0 -> 900 to 1000
            elif logprob >= -1.0:
                conf = 700 + (logprob + 1.0) * 400  # -1.0 to -0.5 -> 700 to 900
            elif logprob >= -2.0:
                conf = 300 + (logprob + 2.0) * 400  # -2.0 to -1.0 -> 300 to 700
            else:
                conf = max(0, 300 + logprob * 150)  # < -2.0 -> 0 to 300
            confidences.append(conf)

        # Combine text
        text = " ".join(texts).strip()

        # Average confidence
        confidence = sum(confidences) / len(confidences) if confidences else 0.0

        # Show segment details
        if logprobs:
            avg_logprob = sum(logprobs) / len(logprobs)
            print(f"DEBUG: Segments: {len(texts)}, avg_logprob: {avg_logprob:.3f}", file=sys.stderr)

        return text, confidence


def main():
    if len(sys.argv) != 3:
        print("Usage: faster_whisper_engine.py model_path sample_rate", file=sys.stderr)
        sys.exit(1)

    model_path = sys.argv[1]
    sample_rate = sys.argv[2]

    # Force line buffering for immediate I/O
    sys.stdout.reconfigure(line_buffering=True)
    sys.stderr.reconfigure(line_buffering=True)

    try:
        # Create engine
        engine = FasterWhisperEngine(model_path, sample_rate)

        # Send startup status
        engine.send_startup_message()

        # Run command loop
        engine.run()

    except Exception as e:
        print(f"ERROR: Engine failed to start: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
