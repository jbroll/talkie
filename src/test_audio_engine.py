#!/usr/bin/env python3
"""
Test faster-whisper engine with real audio file
"""

import sys
import json
import subprocess
import wave
import numpy as np

def resample_audio(audio_data, orig_rate, target_rate):
    """Simple linear interpolation resampling"""
    if orig_rate == target_rate:
        return audio_data

    # Calculate the ratio
    ratio = target_rate / orig_rate
    new_length = int(len(audio_data) * ratio)

    # Simple linear interpolation
    indices = np.linspace(0, len(audio_data) - 1, new_length)
    resampled = np.interp(indices, np.arange(len(audio_data)), audio_data)

    return resampled.astype(np.int16)

def read_wav_file(wav_path):
    """Read WAV file and return int16 PCM data + sample rate"""
    with wave.open(wav_path, 'rb') as wav:
        sample_rate = wav.getframerate()
        n_channels = wav.getnchannels()
        n_frames = wav.getnframes()

        print(f"WAV file info:")
        print(f"  Sample rate: {sample_rate} Hz")
        print(f"  Channels: {n_channels}")
        print(f"  Frames: {n_frames}")
        print(f"  Duration: {n_frames / sample_rate:.2f} seconds")

        # Read audio data
        audio_bytes = wav.readframes(n_frames)

        # Convert to int16 numpy array
        audio_data = np.frombuffer(audio_bytes, dtype=np.int16)

        # If stereo, convert to mono (take left channel)
        if n_channels == 2:
            audio_data = audio_data[::2]

        return audio_data, sample_rate

def test_engine_with_audio(wav_path, model_path):
    """Test the engine with a real audio file"""

    print(f"\n=== Testing Faster-Whisper Engine ===")
    print(f"Audio file: {wav_path}")
    print(f"Model: {model_path}\n")

    # Read WAV file
    audio_data, orig_rate = read_wav_file(wav_path)

    # Resample to 16kHz if needed
    target_rate = 16000
    if orig_rate != target_rate:
        print(f"\nResampling from {orig_rate} Hz to {target_rate} Hz...")
        audio_data = resample_audio(audio_data, orig_rate, target_rate)
        print(f"Resampled audio length: {len(audio_data)} samples")

    # Start engine
    print("\n1. Starting engine...")
    cmd = ['engines/faster_whisper_wrapper.sh', model_path, str(target_rate)]
    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0
    )

    # Read startup response
    startup_line = proc.stdout.readline().decode('utf-8').strip()
    startup = json.loads(startup_line)
    print(f"   Status: {startup['status']}")
    print(f"   Engine: {startup['engine']}")
    print(f"   Version: {startup['version']}")

    # Send audio in chunks (simulate streaming)
    chunk_size = 16000  # 1 second chunks
    num_chunks = (len(audio_data) + chunk_size - 1) // chunk_size

    print(f"\n2. Processing {num_chunks} chunks of audio...")

    for i in range(0, len(audio_data), chunk_size):
        chunk = audio_data[i:i+chunk_size]
        chunk_bytes = chunk.tobytes()

        # Send PROCESS command
        cmd_line = f"PROCESS {len(chunk_bytes)}\n"
        proc.stdin.write(cmd_line.encode('utf-8'))
        proc.stdin.flush()

        # Send binary data
        proc.stdin.write(chunk_bytes)
        proc.stdin.flush()

        # Read response
        response_line = proc.stdout.readline().decode('utf-8').strip()
        response = json.loads(response_line)

        chunk_num = i // chunk_size + 1
        partial = response.get('partial', '')
        print(f"   Chunk {chunk_num}/{num_chunks}: partial='{partial}'")

    # Get final transcription
    print(f"\n3. Getting final transcription...")
    proc.stdin.write(b"FINAL\n")
    proc.stdin.flush()

    final_line = proc.stdout.readline().decode('utf-8').strip()
    final = json.loads(final_line)

    if 'alternatives' in final:
        text = final['alternatives'][0]['text']
        confidence = final['alternatives'][0]['confidence']
        print(f"\n=== Transcription Result ===")
        print(f"Text: {text}")
        print(f"Confidence: {confidence:.3f}")
    elif 'error' in final:
        print(f"\nERROR: {final['error']}")
    else:
        print(f"\nUnexpected response: {final}")

    # Cleanup
    proc.stdin.close()
    proc.wait()

    print(f"\n=== Test Complete ===")

if __name__ == "__main__":
    wav_path = "../test_audio/voice-sample.wav"
    model_path = "../models/faster-whisper"

    test_engine_with_audio(wav_path, model_path)
