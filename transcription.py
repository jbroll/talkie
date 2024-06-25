import vosk
import sounddevice as sd
import numpy as np
import json
import queue
import time
from text_processing import process_text
from logger import get_logger

logger = get_logger()

# Global variables
transcribing = False
total_processing_time = 0
total_chunks_processed = 0
q = None  # Will be initialized in transcribe function
speech_start_time = None

def set_initial_transcription_state(state):
    global transcribing
    transcribing = state
    logger.info(f"Initial transcription state set to: {'ON' if transcribing else 'OFF'}")

def callback(indata, frames, time_info, status):
    global transcribing, q, speech_start_time
    if status:
        logger.debug(f"Status: {status}")
    if transcribing and not q.full():
        # Check if this chunk contains speech (simple energy threshold)
        if speech_start_time is None and np.abs(indata).mean() > 0.01:
            speech_start_time = time.time()
        q.put(bytes(indata))
    elif transcribing and q.full():
        logger.debug("Queue is full, dropping audio data")

def toggle_transcription():
    global transcribing, q, speech_start_time
    transcribing = not transcribing
    logger.info(f"Transcription toggled: {'ON' if transcribing else 'OFF'}")
    if not transcribing:
        # Clear the queue when transcription is turned off
        while not q.empty():
            try:
                q.get_nowait()
            except queue.Empty:
                break
        speech_start_time = None
        logger.debug("Queue cleared")

def transcribe(device_id, samplerate, block_duration, queue_size, model_path):
    global transcribing, total_processing_time, total_chunks_processed, q, speech_start_time

    vosk.SetLogLevel(-1)  # Disable Vosk logging
    logger.info(f"Loading model from: {model_path}")
    model = vosk.Model(model_path)
    rec = vosk.KaldiRecognizer(model, samplerate)
    
    q = queue.Queue(maxsize=queue_size)

    block_size = int(samplerate * block_duration)
    with sd.RawInputStream(samplerate=samplerate, blocksize=block_size, device=device_id, dtype='int16', channels=1, callback=callback):
        logger.info(f"Listening on device: {sd.query_devices(device_id)['name']} at {samplerate} Hz")
        logger.info(f"Block size: {block_size} samples ({block_duration} seconds)")
        logger.info(f"Transcription is {'ON' if transcribing else 'OFF'}")
        
        total_latency = 0
        total_latency_measurements = 0
        
        while True:
            if transcribing:
                try:
                    data = q.get(timeout=0.1)
                    if rec.AcceptWaveform(data):
                        result = json.loads(rec.Result())
                        text = result['text']
                        
                        if text:
                            end_time = time.time()
                            if speech_start_time is not None:
                                latency = end_time - speech_start_time
                                total_latency += latency
                                total_latency_measurements += 1
                                avg_latency = total_latency / total_latency_measurements
                                
                                logger.info(f"Transcribed: {text}")
                                logger.debug(f"End-to-end latency: {latency:.2f}s, Avg latency: {avg_latency:.2f}s")
                                
                                process_text(text)  # This will type the text using xdotool
                                
                                # Reset speech_start_time for the next utterance
                                speech_start_time = None
                            else:
                                logger.info(f"Transcribed: {text}")
                                logger.debug("Latency measurement unavailable for this segment.")
                                process_text(text)  # This will type the text using xdotool
                    
                    total_chunks_processed += 1
                    
                except queue.Empty:
                    # This is now expected behavior when the queue is empty
                    pass
            else:
                time.sleep(0.1)
