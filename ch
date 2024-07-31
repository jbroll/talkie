// @ORDER
imports
constants
globals
logger
setup_logging
list_audio_devices
get_supported_samplerates
select_audio_device
listen_for_hotkey
type_text
smart_capitalize
process_text
set_initial_transcription_state
callback
toggle_transcription
transcribe
uinput_setup
virtual_device
cleanup
main
TKINTER_UI
run

// @imports
import threading
import time
import argparse
import os
import evdev
import logging
from select import select
import sounddevice as sd
import uinput
import string
import vosk
import numpy as np
import json
import queue
import tkinter as tk
from tkinter import scrolledtext
import signal

// @cleanup
def cleanup():
    global transcribing, root
    logger.info("Cleaning up and shutting down...")
    transcribing = False
    if 'root' in globals():
        root.quit()
    logger.info("Cleanup complete.")

// @main
def main():
    global app, root, transcribe_thread, hotkey_thread  # Make these global so they can be accessed in signal handler
    parser = argparse.ArgumentParser(description="Speech-to-Text System using Vosk")
    parser.add_argument("-d", "--device", help="Substring of audio input device name")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose (debug) output")
    parser.add_argument("-m", "--model", help="Path to the Vosk model", default=DEFAULT_MODEL_PATH)
    parser.add_argument("-t", "--transcribe", action="store_true", help="Start transcription immediately")
    args = parser.parse_args()

    # Setup logging
    setup_logging(args.verbose)

    logger.info("Speech-to-Text System using Vosk - Starting up")
    logger.info(f"Using model: {args.model}")
    logger.info(f"Block duration: {BLOCK_DURATION} seconds")
    logger.info(f"Queue size: {QUEUE_SIZE}")

    # Check if the model path exists
    if not os.path.exists(args.model):
        logger.error(f"Model path does not exist: {args.model}")
        return

    logger.debug("Selecting audio device")
    try:
        if args.device:
            device_id, samplerate = select_audio_device(args.device)
        else:
            device_id, samplerate = select_audio_device()

        if device_id is None or samplerate is None:
            logger.error("Failed to select a valid audio device or sample rate.")
            return

        logger.info(f"Selected device ID: {device_id}, Sample rate: {samplerate}")
    except Exception as e:
        logger.error(f"Error during audio device selection: {e}")
        return

    # Set initial transcription state
    set_initial_transcription_state(args.transcribe)

    logger.info("Preparing to start transcription thread")
    try:
        transcribe_thread = threading.Thread(target=transcribe, args=(device_id, samplerate, BLOCK_DURATION, QUEUE_SIZE, args.model))
        logger.info("Transcription thread created")
        
        transcribe_thread.start()
        logger.info("Transcription thread started successfully")
    except Exception as e:
        logger.error(f"Failed to start transcription thread: {e}")
        return

    logger.info("Checking if transcription thread is alive")
    if transcribe_thread.is_alive():
        logger.info("Transcription thread is running")
    else:
        logger.error("Transcription thread is not running")
        return

    logger.debug("Starting hotkey listener thread")
    # Start hotkey listener thread
    hotkey_thread = threading.Thread(target=listen_for_hotkey)
    hotkey_thread.start()

    logger.info(f"Transcription is {'ON' if args.transcribe else 'OFF'} by default.")
    logger.info("Press Meta+E to toggle transcription on/off (works globally).")
    logger.info("Use voice commands like 'period', 'comma', 'question mark', 'exclamation mark', 'new line', or 'new paragraph' for punctuation.")
    logger.info("Use 'delete last word' or 'undo last sentence' for editing.")

    # Set up signal handler for graceful shutdown
    def signal_handler(signum, frame):
        logger.info("Received interrupt signal. Initiating graceful shutdown...")
        cleanup()

    signal.signal(signal.SIGINT, signal_handler)

    # Create and run Tkinter UI
    logger.debug("Initializing Tkinter UI")
    root = tk.Tk()
    app = TalkieUI(root)
    app.update_ui()  # Set initial UI state
    logger.info("GUI initialized. Starting main loop.")
    
    try:
        root.mainloop()
    except KeyboardInterrupt:
        logger.info("Received KeyboardInterrupt in main thread. Initiating graceful shutdown...")
    finally:
        cleanup()

    logger.info("Main loop exited. Shutting down.")