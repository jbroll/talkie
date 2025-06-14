# @imports
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
from tkinter import scrolledtext, Menu
import signal
import sys
import termios
import tty
import atexit
from word2number import w2n
from enum import Enum

# @constants
BLOCK_DURATION = 0.1  # in seconds
QUEUE_SIZE = 5
DEFAULT_MODEL_PATH = "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
MIN_WORD_LENGTH = 2
MAX_NUMBER_BUFFER_SIZE = 20  # Maximum number of words to buffer for number conversion
NUMBER_TIMEOUT = 2.0  # Seconds to wait before processing number buffer

# @state_enum
class ProcessingState(Enum):
    NORMAL = "normal"
    NUMBER = "number"

# @globals
transcribing = False
total_processing_time = 0
total_chunks_processed = 0
q = None  # Will be initialized in transcribe function
speech_start_time = None

last_typed = []
capitalize_next = True
MIN_WORD_LENGTH = 2

# State machine variables
processing_state = ProcessingState.NORMAL
number_buffer = []
number_mode_start_time = None
last_word_time = None

# @process_text
def process_text(text, is_final=False):
    logger.info(f"Processing text: {text}")
    global capitalize_next, processing_state, number_buffer, number_mode_start_time, last_word_time
    
    words = text.split()
    output = []
    current_time = time.time()

    def is_number_word(word):
        """Check if a word can be converted to a number"""
        try:
            w2n.word_to_num(word.lower())
            return True
        except ValueError:
            return False

    def process_number_buffer():
        """Process accumulated number buffer"""
        global processing_state, number_buffer, number_mode_start_time
        
        if number_buffer:
            try:
                number_phrase = ' '.join(number_buffer)
                number = w2n.word_to_num(number_phrase)
                output.append(str(number))
                logger.debug(f"Converted number buffer to: {number}")
                success = True
            except ValueError:
                # Failed to convert - output words as-is
                logger.debug(f"Failed to convert number buffer: {' '.join(number_buffer)}")
                output.extend([smart_capitalize(w) for w in number_buffer])
                success = False
            
            # Reset state
            number_buffer.clear()
            processing_state = ProcessingState.NORMAL
            number_mode_start_time = None
            return success
        return True

    def check_number_timeout():
        """Check if number mode has timed out"""
        if (processing_state == ProcessingState.NUMBER and 
            number_mode_start_time and 
            current_time - number_mode_start_time > NUMBER_TIMEOUT):
            logger.debug("Number mode timed out")
            process_number_buffer()

    # Check for timeout before processing new words
    check_number_timeout()

    for i, word in enumerate(words):
        word_lower = word.lower()
        last_word_time = current_time
        
        # Handle based on current state
        if processing_state == ProcessingState.NORMAL:
            # In NORMAL state
            if is_number_word(word_lower):
                # Transition to NUMBER state
                processing_state = ProcessingState.NUMBER
                number_mode_start_time = current_time
                number_buffer = [word_lower]
                logger.debug(f"Entering NUMBER state with: {word_lower}")
            elif word_lower == "point" and i + 1 < len(words) and is_number_word(words[i + 1].lower()):
                # Look-ahead for "point" followed by number
                processing_state = ProcessingState.NUMBER
                number_mode_start_time = current_time
                number_buffer = [word_lower]
                logger.debug("Entering NUMBER state with 'point'")
            elif word_lower in punctuation:
                # Handle punctuation
                if is_final:  # Only add punctuation for final results
                    output.append(punctuation[word_lower])
                    if punctuation[word_lower] in ['.', '!', '?']:
                        capitalize_next = True
            else:
                # Regular word
                output.append(smart_capitalize(word))
        
        else:  # ProcessingState.NUMBER
            # In NUMBER state
            if is_number_word(word_lower):
                # Continue collecting number words
                if len(number_buffer) < MAX_NUMBER_BUFFER_SIZE:
                    number_buffer.append(word_lower)
                    logger.debug(f"Added to number buffer: {word_lower}")
                else:
                    # Buffer full - process and start new
                    process_number_buffer()
                    processing_state = ProcessingState.NUMBER
                    number_mode_start_time = current_time
                    number_buffer = [word_lower]
            elif word_lower == "and" and len(number_buffer) > 0:
                # "and" is valid in number context
                if len(number_buffer) < MAX_NUMBER_BUFFER_SIZE:
                    number_buffer.append(word_lower)
                    logger.debug("Added 'and' to number buffer")
            elif word_lower == "point":
                # "point" is valid in number context
                if len(number_buffer) < MAX_NUMBER_BUFFER_SIZE:
                    number_buffer.append(word_lower)
                    logger.debug("Added 'point' to number buffer")
            elif word_lower in punctuation:
                # Punctuation ends number mode
                process_number_buffer()
                if is_final:
                    output.append(punctuation[word_lower])
                    if punctuation[word_lower] in ['.', '!', '?']:
                        capitalize_next = True
            else:
                # Non-number word ends number mode
                process_number_buffer()
                output.append(smart_capitalize(word))

    # Handle any remaining buffer at the end
    if is_final and number_buffer:
        process_number_buffer()
    
    # Only check timeout if we're still collecting numbers and this is a partial result
    elif not is_final and processing_state == ProcessingState.NUMBER:
        # Keep the buffer for next partial/final result
        pass

    result = ' '.join(output)
    if is_final:
        result = result.strip()

    if result:  # Only type if there's something to type
        type_text(result + (' ' if not is_final else ''))
        logger.info(f"Processed and typed text: {result}")

# @transcribe
def transcribe(device_id, samplerate, block_duration, queue_size, model_path):
    global transcribing, q, speech_start_time, app, running, processing_state, number_buffer, number_mode_start_time

    print("Transcribe function started")
    logger.info("Transcribe function started")

    vosk.SetLogLevel(-1)  # Disable Vosk logging
    logger.info("Loading Vosk model...")
    model = vosk.Model(model_path)
    logger.info("Vosk model loaded successfully")
    rec = vosk.KaldiRecognizer(model, samplerate)
    rec.SetWords(True)  # Enable word timings
    logger.info("KaldiRecognizer initialized with word timings enabled")
    
    q = queue.Queue(maxsize=queue_size)
    logger.info(f"Queue initialized with max size: {queue_size}")

    block_size = int(samplerate * block_duration)
    logger.info(f"Calculated block size: {block_size}")

    last_partial = ""
    last_sent_text = ""
    STABILITY_THRESHOLD = 5

    logger.info("Initializing audio stream...")
    try:
        with sd.RawInputStream(samplerate=samplerate, blocksize=block_size, device=device_id, dtype='int16', channels=1, callback=callback):
            logger.info(f"Audio stream initialized: device={device_id}, samplerate={samplerate} Hz")
            logger.info(f"Initial transcription state: {'ON' if transcribing else 'OFF'}")
            
            print("Entering main processing loop")
            logger.info("Entering main processing loop")
            while running:
                if transcribing:
                    try:
                        # Check for number timeout even when no new audio
                        if processing_state == ProcessingState.NUMBER and number_mode_start_time:
                            if time.time() - number_mode_start_time > NUMBER_TIMEOUT:
                                logger.debug("Number timeout in main loop")
                                # Process the timeout by sending empty text to trigger buffer processing
                                process_text("", is_final=True)
                        
                        data = q.get(timeout=0.1)
                        if rec.AcceptWaveform(data):
                            result = json.loads(rec.Result())
                            if result.get('text'):
                                final_text = result['text']
                                logger.info(f"Final: {final_text}")
                                
                                # Process only the part of final text that hasn't been sent yet
                                if final_text.startswith(last_sent_text):
                                    unsent_text = final_text[len(last_sent_text):].strip()
                                    if unsent_text:
                                        process_text(unsent_text, is_final=True)
                                else:
                                    # If the final text doesn't match what we've sent, send the whole thing
                                    process_text(final_text, is_final=True)
                                
                                app.clear_partial_text()
                                last_sent_text = final_text
                                last_partial = ""
                        else:
                            partial = json.loads(rec.PartialResult())
                            if partial.get('partial'):
                                new_partial = partial['partial']
                                if new_partial != last_partial:
                                    logger.debug(f"Partial: {new_partial}")
                                    
                                    # Split the new partial into words
                                    new_words = new_partial.split()
                                    
                                    # Find the common prefix between last_sent_text and new_partial
                                    common_prefix = os.path.commonprefix([last_sent_text, new_partial])
                                    common_word_count = len(common_prefix.split())
                                    
                                    # Identify new stable text
                                    if len(new_words) - common_word_count >= STABILITY_THRESHOLD:
                                        stable_text = ' '.join(new_words[:len(new_words) - STABILITY_THRESHOLD + 1])
                                        if stable_text != last_sent_text:
                                            # Send only the new stable text
                                            new_text_to_send = stable_text[len(last_sent_text):].strip()
                                            if new_text_to_send:
                                                process_text(new_text_to_send, is_final=False)
                                                last_sent_text = stable_text
                                    
                                    # Update the partial text display
                                    sent_word_count = len(last_sent_text.split())
                                    display_text = ' '.join(['<sent>' + w + '</sent>' if i < sent_word_count else w for i, w in enumerate(new_words)])
                                    app.update_partial_text(display_text)
                                    
                                    last_partial = new_partial
                    except queue.Empty:
                        logger.debug("Queue empty, continuing")
                        # Still check for timeout even with empty queue
                        if processing_state == ProcessingState.NUMBER and number_mode_start_time:
                            if time.time() - number_mode_start_time > NUMBER_TIMEOUT:
                                logger.debug("Number timeout on empty queue")
                                process_text("", is_final=True)
                else:
                    logger.debug("Transcription is off, waiting")
                    # Reset state when transcription is off
                    if processing_state == ProcessingState.NUMBER:
                        processing_state = ProcessingState.NORMAL
                        number_buffer.clear()
                        number_mode_start_time = None
                    time.sleep(0.1)
    except Exception as e:
        logger.error(f"Error in audio stream: {e}")
        print(f"Error in audio stream: {e}")

    logger.info("Transcribe function ending")
    print("Transcribe function ending")

# @ORDER
imports
constants
state_enum
globals
punctuation
logger
smart_capitalize
process_text
set_initial_transcription_state
callback
toggle_transcription
transcribe
list_audio_devices
get_supported_samplerates
select_audio_device
listen_for_hotkey
type_text
uinput_setup
virtual_device
cleanup
restore_terminal
tk_cleanup
keyboard_interrupt_monitor
TKINTER_UI
main
run
