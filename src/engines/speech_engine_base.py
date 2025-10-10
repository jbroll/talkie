#!/usr/bin/env python3
"""
Base class for coprocess speech engines.

Provides common functionality for:
- Binary audio buffering
- Command protocol (PROCESS, FINAL, RESET, MODEL)
- Sample rate handling
- Vosk-format JSON responses
- PyAV resampling

Subclasses must implement:
- load_model(model_path) -> bool
- transcribe_audio(audio_float32_16khz) -> (text, confidence)
"""

import sys
import json
import numpy as np
import av
from av.audio.resampler import AudioResampler


class SpeechEngineBase:
    """Base class for speech recognition engines using coprocess protocol"""

    def __init__(self, model_path, sample_rate, engine_name, version="1.0"):
        """Initialize engine

        Args:
            model_path: Path to model file/directory
            sample_rate: Input audio sample rate (from device)
            engine_name: Name for status messages
            version: Engine version string
        """
        # Handle both int and float strings
        self.sample_rate = int(float(sample_rate))
        self.target_sample_rate = 16000  # Whisper/Sherpa standard
        self.buffer = []
        self.model = None
        self.engine_name = engine_name
        self.version = version

        print(f"Engine initialized: {engine_name} v{version}", file=sys.stderr)
        print(f"  Input sample rate: {self.sample_rate}Hz", file=sys.stderr)
        print(f"  Target sample rate: {self.target_sample_rate}Hz", file=sys.stderr)

        # Load model (implemented by subclass)
        if not self.load_model(model_path):
            raise RuntimeError(f"Failed to load model: {model_path}")

    def load_model(self, model_path):
        """Load speech recognition model

        Subclasses must implement this method.

        Args:
            model_path: Path to model file/directory

        Returns:
            bool: True if successful, False otherwise
        """
        raise NotImplementedError("Subclass must implement load_model()")

    def transcribe_audio(self, audio):
        """Transcribe audio buffer

        Subclasses must implement this method.

        Args:
            audio: numpy float32 array at 16kHz sample rate

        Returns:
            tuple: (text, confidence) where confidence is in 0-1000 range
        """
        raise NotImplementedError("Subclass must implement transcribe_audio()")

    def resample_audio(self, audio, orig_sr, target_sr):
        """Resample audio using PyAV (FFmpeg's libswresample - high quality)"""
        if orig_sr == target_sr:
            return audio

        # Create resampler
        resampler = AudioResampler(
            format='s16',
            layout='mono',
            rate=target_sr
        )

        # Convert float32 [-1, 1] to int16
        audio_int16 = (audio * 32768).clip(-32768, 32767).astype(np.int16)

        # Create audio frame
        frame = av.AudioFrame.from_ndarray(
            audio_int16.reshape(1, -1),
            format='s16',
            layout='mono'
        )
        frame.sample_rate = orig_sr

        # Resample
        resampled_frames = resampler.resample(frame)

        # Convert back to float32
        if resampled_frames:
            resampled_int16 = resampled_frames[0].to_ndarray()[0]
            resampled_float32 = resampled_int16.astype(np.float32) / 32768.0
            return resampled_float32
        else:
            # Fallback to original if resampling fails
            print("WARNING: PyAV resampling failed, using original audio", file=sys.stderr)
            return audio

    def cmd_process(self, byte_count, stdin_binary):
        """PROCESS byte_count
        [binary audio data]

        Accumulates audio in buffer for batch processing.
        Returns empty partial (batch mode).
        """
        byte_count = int(byte_count)

        # Read binary audio from stdin
        audio_bytes = stdin_binary.read(byte_count)

        if len(audio_bytes) != byte_count:
            response = {"error": f"expected {byte_count} bytes, got {len(audio_bytes)}"}
            print(json.dumps(response), flush=True)
            return

        # Convert int16 PCM to float32
        audio_int16 = np.frombuffer(audio_bytes, dtype=np.int16)
        audio_float32 = audio_int16.astype(np.float32) / 32768.0

        # Accumulate in buffer
        self.buffer.extend(audio_float32)

        # Batch mode: no partials, just acknowledge
        response = {"partial": ""}
        print(json.dumps(response), flush=True)

    def cmd_final(self):
        """FINAL

        Transcribes accumulated audio buffer and clears it.
        Returns Vosk-format JSON with alternatives.
        """
        buffer_len = len(self.buffer)
        print(f"DEBUG: FINAL called, buffer size: {buffer_len} samples", file=sys.stderr)

        if not self.buffer or not self.model:
            response = {
                "alternatives": [
                    {"text": "", "confidence": 0.0}
                ]
            }
            print(json.dumps(response), flush=True)
            self.buffer = []
            return

        try:
            # Convert buffer to numpy array
            audio = np.array(self.buffer, dtype=np.float32)
            duration = len(audio) / self.sample_rate
            print(f"DEBUG: Original audio: {duration:.2f}s at {self.sample_rate}Hz", file=sys.stderr)

            # Resample to 16kHz if needed
            if self.sample_rate != self.target_sample_rate:
                audio = self.resample_audio(audio, self.sample_rate, self.target_sample_rate)
                print(f"DEBUG: Resampled to {len(audio)} samples at {self.target_sample_rate}Hz", file=sys.stderr)

            # Transcribe (implemented by subclass)
            print(f"DEBUG: Transcribing {len(audio)/self.target_sample_rate:.2f}s of audio...", file=sys.stderr)
            text, confidence = self.transcribe_audio(audio)
            print(f"DEBUG: Transcribed text: '{text}' (conf: {confidence:.1f})", file=sys.stderr)

            # Vosk-format response
            response = {
                "alternatives": [
                    {"text": text, "confidence": confidence}
                ]
            }

            print(json.dumps(response), flush=True)

        except Exception as e:
            response = {"error": f"transcription_failed: {e}"}
            print(json.dumps(response), flush=True)
            # Print traceback to stderr
            import traceback
            traceback.print_exc(file=sys.stderr)

        finally:
            # Always clear buffer
            self.buffer = []

    def cmd_reset(self):
        """RESET

        Clears audio buffer.
        """
        self.buffer = []
        response = {"status": "ok"}
        print(json.dumps(response), flush=True)

    def cmd_model(self, model_path):
        """MODEL model_path

        Loads a different model.
        """
        # Clear buffer when changing models
        self.buffer = []

        if self.load_model(model_path):
            response = {"status": "ok", "model": model_path}
            print(json.dumps(response), flush=True)
        else:
            response = {"error": f"failed to load model: {model_path}"}
            print(json.dumps(response), flush=True)

    def run(self):
        """Main command loop - uses binary stdin consistently"""
        # Use binary mode for all stdin operations
        stdin_binary = sys.stdin.buffer

        while True:
            try:
                # Read command line in binary mode
                line_bytes = stdin_binary.readline()
                if not line_bytes:
                    # EOF - exit gracefully
                    break

                # Decode command line
                try:
                    line = line_bytes.decode('utf-8').strip()
                except UnicodeDecodeError:
                    # Skip malformed lines
                    continue

                # Parse command
                parts = line.split(None, 1)
                if not parts:
                    continue

                cmd = parts[0]
                args = parts[1] if len(parts) > 1 else ""

                # Dispatch command
                if cmd == "PROCESS":
                    self.cmd_process(args, stdin_binary)
                elif cmd == "FINAL":
                    self.cmd_final()
                elif cmd == "RESET":
                    self.cmd_reset()
                elif cmd == "MODEL":
                    self.cmd_model(args)
                else:
                    response = {"error": f"unknown_command: {cmd}"}
                    print(json.dumps(response), flush=True)

            except Exception as e:
                response = {"error": f"exception: {type(e).__name__}: {e}"}
                print(json.dumps(response), flush=True)
                # Print to stderr for debugging
                import traceback
                traceback.print_exc(file=sys.stderr)

    def send_startup_message(self):
        """Send initial status message to confirm engine is ready"""
        startup = {
            "status": "ok",
            "engine": self.engine_name,
            "version": self.version,
            "sample_rate": self.sample_rate
        }
        print(json.dumps(startup), flush=True)
