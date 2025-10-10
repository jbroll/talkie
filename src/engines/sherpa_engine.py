#!/usr/bin/env python3
"""
Sherpa-ONNX Speech Engine - Coprocess Implementation

Inherits from SpeechEngineBase for common functionality.
Implements Sherpa-ONNX-specific model loading and transcription.
"""

import sys
import os
import numpy as np
from speech_engine_base import SpeechEngineBase

# Import sherpa-onnx
try:
    import sherpa_onnx
except ImportError:
    print("ERROR: sherpa_onnx module not found", file=sys.stderr)
    print("Install with: pip install sherpa-onnx", file=sys.stderr)
    sys.exit(1)


class SherpaEngine(SpeechEngineBase):
    """Sherpa-ONNX implementation of speech recognition engine"""

    def __init__(self, model_path, sample_rate):
        # Initialize base class
        super().__init__(model_path, sample_rate, "sherpa-onnx", "1.0")

        # Sherpa-specific: create recognizer stream
        self.recognizer_stream = None

    def load_model(self, model_path):
        """Load Sherpa-ONNX model"""
        try:
            # Check if model directory exists
            if not os.path.isdir(model_path):
                print(f"ERROR: Model directory not found: {model_path}", file=sys.stderr)
                return False

            # Build paths to model files
            encoder = os.path.join(model_path, "encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx")
            decoder = os.path.join(model_path, "decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx")
            joiner = os.path.join(model_path, "joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx")
            tokens = os.path.join(model_path, "tokens.txt")

            # Verify files exist
            for filepath in [encoder, decoder, joiner, tokens]:
                if not os.path.exists(filepath):
                    print(f"ERROR: Required file not found: {filepath}", file=sys.stderr)
                    return False

            # Create recognizer
            self.model = sherpa_onnx.OnlineRecognizer.from_transducer(
                tokens=tokens,
                encoder=encoder,
                decoder=decoder,
                joiner=joiner,
                num_threads=2,
                sample_rate=self.target_sample_rate,
                feature_dim=80,
                enable_endpoint_detection=False,  # We handle this
                decoding_method="greedy_search"
            )

            print(f"✓ Sherpa-ONNX model loaded: {model_path}", file=sys.stderr)
            return True

        except Exception as e:
            print(f"ERROR: Failed to load Sherpa model: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc(file=sys.stderr)
            return False

    def transcribe_audio(self, audio):
        """Transcribe audio using Sherpa-ONNX

        Args:
            audio: numpy float32 array at 16kHz

        Returns:
            tuple: (text, confidence) in Vosk-compatible format
        """
        # Create a new stream for this utterance
        stream = self.model.create_stream()

        # Feed audio in chunks (Sherpa processes streaming)
        chunk_size = 1600  # 100ms at 16kHz
        for i in range(0, len(audio), chunk_size):
            chunk = audio[i:i+chunk_size]
            stream.accept_waveform(self.target_sample_rate, chunk)

        # Signal end of input
        stream.input_finished()

        # Get final result
        while self.model.is_ready(stream):
            self.model.decode_stream(stream)

        # get_result() returns a string directly (not an object)
        # Convert to lowercase since Sherpa returns all caps
        text = self.model.get_result(stream).strip().lower()

        # Sherpa doesn't provide confidence scores directly
        # Use a heuristic: longer text = higher confidence
        # Map length to confidence (empty = 0, 10+ words = 900+)
        word_count = len(text.split())
        if word_count == 0:
            confidence = 0.0
        elif word_count >= 10:
            confidence = 900.0
        else:
            # Linear scaling: 1 word = 500, 10 words = 900
            confidence = 500 + (word_count - 1) * (400 / 9)

        print(f"DEBUG: Word count: {word_count}, confidence: {confidence:.1f}", file=sys.stderr)

        return text, confidence


def main():
    if len(sys.argv) != 3:
        print("Usage: sherpa_engine.py model_path sample_rate", file=sys.stderr)
        sys.exit(1)

    model_path = sys.argv[1]
    sample_rate = sys.argv[2]

    # Force line buffering for immediate I/O
    sys.stdout.reconfigure(line_buffering=True)
    sys.stderr.reconfigure(line_buffering=True)

    try:
        # Create engine
        engine = SherpaEngine(model_path, sample_rate)

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
