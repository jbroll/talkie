#!/home/john/src/talkie/bin/python3

import threading
import time
import argparse
import os
from audio_device import select_audio_device, list_audio_devices
from transcription import transcribe, set_initial_transcription_state
from hotkey_listener import listen_for_hotkey
from logger import setup_logging, get_logger

# Adjustable parameters
BLOCK_DURATION = 0.1  # in seconds
QUEUE_SIZE = 5
DEFAULT_MODEL_PATH = "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"

def main():
    parser = argparse.ArgumentParser(description="Speech-to-Text System using Vosk")
    parser.add_argument("-d", "--device", help="Substring of audio input device name")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose (debug) output")
    parser.add_argument("-m", "--model", help="Path to the Vosk model", default=DEFAULT_MODEL_PATH)
    parser.add_argument("-t", "--transcribe", action="store_true", help="Start transcription immediately")
    args = parser.parse_args()

    # Setup logging
    setup_logging(args.verbose)
    logger = get_logger()

    logger.info("Speech-to-Text System using Vosk")
    logger.info(f"Using model: {args.model}")
    logger.info(f"Block duration: {BLOCK_DURATION} seconds")
    logger.info(f"Queue size: {QUEUE_SIZE}")

    # Check if the model path exists
    if not os.path.exists(args.model):
        logger.error(f"Model path does not exist: {args.model}")
        return

    if args.device:
        device_id, samplerate = select_audio_device(args.device)
    else:
        device_id, samplerate = select_audio_device()

    if device_id is None:
        logger.error("No suitable audio device found. Exiting.")
        return

    # Set initial transcription state
    set_initial_transcription_state(args.transcribe)

    # Start transcription thread
    transcribe_thread = threading.Thread(target=transcribe, args=(device_id, samplerate, BLOCK_DURATION, QUEUE_SIZE, args.model))
    transcribe_thread.start()

    # Start hotkey listener thread
    hotkey_thread = threading.Thread(target=listen_for_hotkey)
    hotkey_thread.start()

    logger.info(f"Transcription is {'ON' if args.transcribe else 'OFF'} by default.")
    logger.info("Press Meta+E to toggle transcription on/off (works globally).")
    logger.info("Use voice commands like 'period', 'comma', 'question mark', 'exclamation mark', 'new line', or 'new paragraph' for punctuation.")
    logger.info("Use 'delete last word' or 'undo last sentence' for editing.")

    # Keep the main thread alive
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        logger.info("\nExiting...")

if __name__ == "__main__":
    main()
