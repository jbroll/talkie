#!/home/john/src/talkie/bin/python3
#

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
import numpy as np
import json
import queue
import tkinter as tk
from tkinter import scrolledtext, Menu, ttk
import signal
import sys
import termios
import tty
import atexit
from word2number import w2n
from enum import Enum
from pathlib import Path

from JSONFileMonitor import JSONFileMonitor
from speech.speech_engine import SpeechManager, SpeechEngineType, SpeechResult
import os

# @constants
BLOCK_DURATION = 0.1  # in seconds
QUEUE_SIZE = 5
DEFAULT_MODEL_PATH = "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
MIN_WORD_LENGTH = 2
MAX_NUMBER_BUFFER_SIZE = 20  # Maximum number of words to buffer for number conversion
NUMBER_TIMEOUT = 2.0  # Seconds to wait before processing number buffer

# Config file management
CONFIG_FILE = Path.home() / ".talkie.conf"
DEFAULT_CONFIG = {
    "audio_device": "pulse",
    "voice_threshold": 50.0,
    "silence_trailing_duration": 0.5,
    "speech_timeout": 3.0,
    "engine": "vosk",
    "model_path": DEFAULT_MODEL_PATH
}

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

# Configurable speech detection parameters
voice_threshold = 50.0  # Voice activity detection threshold (int16 scale: 0-32767)
current_audio_energy = 0.0  # Current audio energy level for display

# Speech utterance completion parameters (configurable)
silence_trailing_duration = 0.5  # Seconds of silence to send after speech ends
speech_timeout = 3.0  # Max seconds without finalizing before forcing result
silence_frames_sent = 0
max_silence_frames = 0  # Will be calculated based on sample rate
last_speech_time = None

# Lookback buffer for catching word leading edges
previous_audio_buffer = None

# Utterance boundary tracking for proper spacing
last_utterance_completed = False

# State machine variables
processing_state = ProcessingState.NORMAL
number_buffer = []
number_mode_start_time = None
last_word_time = None

# @punctuation
punctuation = {
    "period": ".",
    "comma": ",",
    "question mark": "?",
    "exclamation mark": "!",
    "exclamation point": "!",
    "colon": ":",
    "semicolon": ";",
    "dash": "-",
    "hyphen": "-",
    "underscore": "_",
    "plus": "+",
    "equals": "=",
    "at sign": "@",
    "hash": "#",
    "dollar sign": "$",
    "percent": "%",
    "caret": "^",
    "ampersand": "&",
    "asterisk": "*",
    "left parenthesis": "(",
    "right parenthesis": ")",
    "left bracket": "[",
    "right bracket": "]",
    "left brace": "{",
    "right brace": "}",
    "backslash": "\\",
    "forward slash": "/",
    "vertical bar": "|",
    "less than": "<",
    "greater than": ">",
    "tilde": "~",
    "backtick": "`",
    "single quote": "'",
    "double quote": '"',
    "new line": "\n",
    "new paragraph": "\n\n"
}

running = True  # Global flag to control thread execution
cleanup_done = False  # Flag to prevent multiple cleanup calls
original_terminal_settings = None
tk_root = None  # Global reference to Tkinter root

# @logger
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def setup_logging(verbose=False):
    global logger
    # Remove all handlers associated with the logger object
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)
    
    # Set the logging level based on the verbose flag
    level = logging.DEBUG if verbose else logging.INFO
    
    # Configure the logger
    logger.setLevel(level)
    
    # Create console handler and set level
    ch = logging.StreamHandler()
    ch.setLevel(level)
    
    # Create formatter
    formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
    
    # Add formatter to ch
    ch.setFormatter(formatter)
    
    # Add ch to logger
    logger.addHandler(ch)

    # Disable propagation to the root logger
    logger.propagate = False

# @config_management
def load_config():
    """Load configuration from JSON file, creating default if not exists"""
    global voice_threshold, silence_trailing_duration, speech_timeout
    
    try:
        if CONFIG_FILE.exists():
            with open(CONFIG_FILE, 'r') as f:
                config = json.load(f)
            logger.info(f"Loaded config from {CONFIG_FILE}")
        else:
            config = DEFAULT_CONFIG.copy()
            save_config(config)
            logger.info(f"Created default config at {CONFIG_FILE}")
        
        # Update global variables from config
        voice_threshold = config.get("voice_threshold", DEFAULT_CONFIG["voice_threshold"])
        silence_trailing_duration = config.get("silence_trailing_duration", DEFAULT_CONFIG["silence_trailing_duration"])
        speech_timeout = config.get("speech_timeout", DEFAULT_CONFIG["speech_timeout"])
        
        return config
        
    except Exception as e:
        logger.error(f"Error loading config: {e}")
        return DEFAULT_CONFIG.copy()

def save_config(config):
    """Save configuration to JSON file"""
    try:
        with open(CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=2)
        logger.debug(f"Saved config to {CONFIG_FILE}")
    except Exception as e:
        logger.error(f"Error saving config: {e}")

def update_config_param(key, value):
    """Update a single parameter in the config file"""
    config = load_config()
    config[key] = value
    save_config(config)
    logger.debug(f"Updated config: {key} = {value}")

# @smart_capitalize
def smart_capitalize(text):
    global capitalize_next
    if capitalize_next:
        text = text.capitalize()
        capitalize_next = False
    return text

# @process_text
def process_text(text, is_final=False):
    logger.info(f"Processing text: {text}")
    global capitalize_next, processing_state, number_buffer, number_mode_start_time, last_word_time
    global last_utterance_completed
    
    words = text.split()
    output = []
    current_time = time.time()
    
    # Add space at beginning of new utterance if we just completed a previous utterance
    add_leading_space = False
    if last_utterance_completed and len(words) > 0:
        add_leading_space = True
        last_utterance_completed = False  # Reset the flag
        logger.debug("Adding leading space for new utterance")

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
        # Add leading space for new utterance if needed
        if add_leading_space:
            result = ' ' + result
        
        type_text(result + (' ' if not is_final else ''))
        logger.info(f"Processed and typed text: {result}")
    elif add_leading_space:
        # Even if no words, we might need to add just a space for separation
        type_text(' ')
        logger.debug("Typed leading space for utterance separation")

# @callback
def callback(indata, frames, time_info, status):
    global transcribing, q, speech_start_time, voice_threshold, current_audio_energy
    global silence_frames_sent, max_silence_frames, last_speech_time, previous_audio_buffer
    
    # Always update current_audio_energy for UI display, regardless of transcribing state
    try:
        audio_np = indata.flatten()  # Flatten in case it's 2D
        audio_energy = np.abs(audio_np).mean()
        current_audio_energy = audio_energy  # Update for UI display
        
        # Debug: Show audio processing
        if not hasattr(callback, '_call_count'):
            callback._call_count = 0
        callback._call_count += 1
        
        if callback._call_count % 50 == 0:  # Log every 50 calls
            logger.info(f"Audio callback {callback._call_count}: energy={audio_energy:.1f}, transcribing={transcribing}, threshold={voice_threshold}")
    except Exception as e:
        logger.error(f"Error processing audio in callback: {e}")
        current_audio_energy = 0.0
    
    if status:
        logger.debug(f"Status: {status}")
    if transcribing and not q.full():
        # Voice activity detection logic
        current_time = time.time()
        
        if audio_energy > voice_threshold:
            # Voice detected
            if speech_start_time is None:
                # Transition from silence to speech - send lookback buffer first
                if previous_audio_buffer is not None:
                    q.put(previous_audio_buffer.tobytes())
                    logger.debug("Sent lookback buffer for word leading edge")
                speech_start_time = current_time
                logger.debug("Speech started")
            last_speech_time = current_time
            silence_frames_sent = 0  # Reset silence counter
            # Convert numpy array back to bytes for speech engine compatibility
            q.put(audio_np.tobytes())
        else:
            # No voice detected
            if speech_start_time is not None and silence_frames_sent < max_silence_frames:
                # We were speaking, now send trailing silence for utterance completion
                silence_frames_sent += 1
                # Create silent audio frame (zeros with same shape)
                silent_frame = np.zeros_like(audio_np)
                q.put(silent_frame.tobytes())
                logger.debug(f"Sending silence frame {silence_frames_sent}/{max_silence_frames}")
                
                if silence_frames_sent >= max_silence_frames:
                    logger.debug("Silence trailing complete")
                    speech_start_time = None
            else:
                # Pure silence - reset speech timing if enough time has passed
                if speech_start_time is not None:
                    logger.debug(f"Voice activity ended, energy: {audio_energy:.4f}")
                    speech_start_time = None
        
        # Always store current buffer as potential lookback (only during silence)
        if audio_energy <= voice_threshold:
            previous_audio_buffer = audio_np.copy()
            
    elif transcribing and q.full():
        logger.debug("Queue is full, dropping audio data")

# @set_initial_transcription_state
def set_initial_transcription_state(state):
    global transcribing
    transcribing = state
    logger.info(f"Initial transcription state set to: {'ON' if transcribing else 'OFF'}")

# @set_transcribing
def set_transcribing(state):
    global transcribing
    transcribing = state

    logger.info(f"Transcription: {'ON' if transcribing else 'OFF'}")
    if not transcribing:
        # Clear the queue when transcription is turned off
        while not q.empty():
            try:
                q.get_nowait()
            except queue.Empty:
                break
        speech_start_time = None
        logger.debug("Queue cleared")
    
    # Update UI if it exists
    if 'app' in globals():
        app.update_ui()

# @toggle_transcription
def toggle_transcription():
    global transcribing, q, speech_start_time
    transcribing = not transcribing
    set_transcribing(transcribing)

def on_file_change(state):
    set_transcribing(state.transcribing)

# @transcribe
def transcribe(device_id, samplerate, block_duration, queue_size, engine_config):
    global transcribing, q, speech_start_time, app, running, processing_state, number_buffer, number_mode_start_time
    global max_silence_frames, last_speech_time

    print("Transcribe function started")
    logger.info("Transcribe function started")
    
    # Calculate how many frames of silence to send for utterance completion
    max_silence_frames = int(silence_trailing_duration / block_duration)
    logger.info(f"Will send {max_silence_frames} silence frames ({silence_trailing_duration}s) after speech ends")

    # Initialize speech manager with selected engine
    def handle_speech_result(result: SpeechResult):
        global last_utterance_completed
        if transcribing:
            if result.is_final:
                logger.info(f"Final: {result.text}")
                process_text(result.text, is_final=True)
                last_utterance_completed = True  # Mark that we completed an utterance
                if app:
                    app.clear_partial_text()
            else:
                logger.debug(f"Partial: {result.text}")
                if app:
                    app.update_partial_text(result.text)

    # Create speech manager with fallback
    engine_type = engine_config.pop('engine_type')
    speech_manager = SpeechManager(
        engine_type=engine_type,
        result_callback=handle_speech_result,
        **engine_config
    )
    
    if not speech_manager.initialize():
        logger.error(f"Failed to initialize {engine_type.value} engine")
        
        # Try fallback to Vosk if sherpa-onnx failed
        if engine_type == SpeechEngineType.SHERPA_ONNX:
            logger.info("Attempting fallback to Vosk engine...")
            speech_manager = SpeechManager(
                engine_type=SpeechEngineType.VOSK,
                result_callback=handle_speech_result,
                model_path=DEFAULT_MODEL_PATH,
                samplerate=samplerate  # Use actual device sample rate
            )
            
            if not speech_manager.initialize():
                logger.error("Failed to initialize Vosk fallback engine")
                return
            else:
                logger.info("Successfully fell back to Vosk engine")
        else:
            return
        
    # Don't start separate thread - we'll process directly in main loop
    # speech_manager.start()
    
    # Initialize audio queue and processing
    q = queue.Queue(maxsize=queue_size)
    block_size = int(samplerate * block_duration)
    
    file_monitor = JSONFileMonitor(Path.home() / ".talkie", on_file_change)
    file_monitor.start()

    if device_id is not None:
        logger.info("Initializing audio stream...")
        try:
            with sd.InputStream(samplerate=samplerate, blocksize=block_size, 
                               device=device_id, dtype='int16', channels=1, 
                               callback=callback):
                logger.info(f"Audio stream initialized: device={device_id}, samplerate={samplerate} Hz")
                
                # Run the main processing loop
                run_main_loop(speech_manager, handle_speech_result)
                
        except Exception as e:
            logger.error(f"Error in audio stream: {e}")
            print(f"Error in audio stream: {e}")
        finally:
            if speech_manager:
                speech_manager.cleanup()
            file_monitor.stop()
    else:
        logger.info("No audio device configured. Starting without audio stream - use UI to select device.")
        # Run without audio stream - just the UI and file monitor
        try:
            # Run the main processing loop without audio
            run_main_loop(speech_manager, handle_speech_result)
        finally:
            if speech_manager:
                speech_manager.cleanup()
            file_monitor.stop()

def run_main_loop(speech_manager, handle_speech_result):
    """Main processing loop that can run with or without audio"""
    global running, processing_state, number_buffer, number_mode_start_time, last_speech_time
    
    while running:
        if transcribing:
            try:
                # Handle number timeout
                if processing_state == ProcessingState.NUMBER and number_mode_start_time:
                    if time.time() - number_mode_start_time > NUMBER_TIMEOUT:
                        logger.debug("Number timeout in main loop")
                        process_text("", is_final=True)
                
                # Handle speech timeout - force final result if speech has been going too long
                if last_speech_time and time.time() - last_speech_time > speech_timeout:
                    logger.debug("Speech timeout - forcing final result")
                    final_result = speech_manager.adapter.get_final_result()
                    if final_result:
                        handle_speech_result(final_result)
                    # Reset speech engine for next utterance
                    speech_manager.adapter.reset()
                    last_speech_time = None
                
                # Get audio data and process directly (like working version)
                data = q.get(timeout=0.1)
                result = speech_manager.adapter.process_audio(data)
                if result:
                    handle_speech_result(result)
                
            except queue.Empty:
                # Handle timeout logic
                if processing_state == ProcessingState.NUMBER and number_mode_start_time:
                    if time.time() - number_mode_start_time > NUMBER_TIMEOUT:
                        logger.debug("Number timeout on empty queue")
                        process_text("", is_final=True)
                        
                # Handle speech timeout in empty queue case too
                if last_speech_time and time.time() - last_speech_time > speech_timeout:
                    logger.debug("Speech timeout on empty queue - forcing final result")
                    final_result = speech_manager.adapter.get_final_result()
                    if final_result:
                        handle_speech_result(final_result)
                    speech_manager.adapter.reset()
                    last_speech_time = None
        else:
            # Reset logic when transcription is off
            if processing_state == ProcessingState.NUMBER:
                processing_state = ProcessingState.NORMAL
                number_buffer.clear()
                number_mode_start_time = None
            time.sleep(0.1)

# @list_audio_devices
def list_audio_devices():
    logger.info("Available audio input devices:")
    devices = sd.query_devices()
    for i, device in enumerate(devices):
        if device['max_input_channels'] > 0:
            logger.info(f"{i}: {device['name']}")
    return devices

def get_input_devices_for_ui():
    """Get a list of input devices formatted for UI dropdown"""
    devices = sd.query_devices()
    input_devices = []
    for i, device in enumerate(devices):
        if device['max_input_channels'] > 0:
            # Format: "device_name (ID: device_id)"
            display_name = f"{device['name']} (ID: {i})"
            input_devices.append((display_name, i, device['name']))
    return input_devices

# @get_supported_samplerates
def get_supported_samplerates(device_id):
    device_info = sd.query_devices(device_id, 'input')
    try:
        supported_rates = [
            int(rate) for rate in device_info['default_samplerate'].split(',')
        ]
    except AttributeError:
        supported_rates = [int(device_info['default_samplerate'])]
    
    logger.debug(f"Supported sample rates for this device: {supported_rates}")
    return supported_rates

# @select_audio_device
def select_audio_device(device_substring=None, config=None):
    devices = list_audio_devices()
    
    # If no device specified, try to use config
    if not device_substring and config:
        device_substring = config.get("audio_device")
        logger.info(f"Using audio device from config: {device_substring}")
    
    if device_substring:
        device_id = None
        device_info = None
        
        # First try numeric input (existing behavior)
        try:
            device_id = int(device_substring)
            if 0 <= device_id < len(devices) and devices[device_id]['max_input_channels'] > 0:
                device_info = devices[device_id]
                logger.info(f"Selected device by number: {device_info['name']}")
            else:
                logger.error(f"Device {device_id} not found or has no input channels.")
                return None, None
        except ValueError:
            # Not a number, try name matching
            # Common device name aliases
            device_aliases = {
                'pulse': 'pulse',
                'default': 'default',
                'system': 'sysdefault',
                'sys': 'sysdefault'
            }
            
            # Check aliases first
            search_term = device_aliases.get(device_substring.lower(), device_substring.lower())
            
            matching_devices = [
                (i, device) for i, device in enumerate(devices)
                if device['max_input_channels'] > 0 and search_term in device['name'].lower()
            ]
            
            if matching_devices:
                if len(matching_devices) > 1:
                    logger.info("Multiple matching devices found:")
                    for i, device in matching_devices:
                        logger.info(f"{i}: {device['name']}")
                    # Auto-select the first matching device (prefer exact matches)
                    exact_matches = [d for d in matching_devices if search_term == d[1]['name'].lower()]
                    if exact_matches:
                        device_id, device_info = exact_matches[0]
                        logger.info(f"Selected exact match: {device_info['name']}")
                    else:
                        device_id, device_info = matching_devices[0]
                        logger.info(f"Selected first match: {device_info['name']}")
                else:
                    device_id, device_info = matching_devices[0]
                
                logger.info(f"Selected device: {device_info['name']}")
            else:
                logger.error(f"No device matching '{device_substring}' found.")
                return None, None
    else:
        # No device specified and no config - use defaults
        logger.error("No audio device specified. Use --device <name> or configure in ~/.talkie.conf")
        logger.info("Available devices:")
        for i, device in enumerate(devices):
            if device['max_input_channels'] > 0:
                logger.info(f"  {i}: {device['name']}")
        logger.info("Example: ./talkie.sh --device pulse")
        return None, None
    
    supported_rates = get_supported_samplerates(device_id)
    if not supported_rates:
        logger.error("No supported sample rates found for this device.")
        return None, None
    
    preferred_rates = [r for r in supported_rates if r <= 16000]
    if preferred_rates:
        samplerate = max(preferred_rates)
    else:
        samplerate = min(supported_rates)
    logger.info(f"Selected sample rate: {samplerate} Hz")
    
    return device_id, samplerate

# @type_text
def type_text(text):
    logger.debug(f"Typing text: {text}")
    for char in text:
        if char.isupper():
            device.emit_combo((uinput.KEY_LEFTSHIFT, getattr(uinput, f'KEY_{char.upper()}')))
        elif char in special_char_map:
            device.emit_combo(special_char_map[char])
        elif char == ' ':
            device.emit_click(uinput.KEY_SPACE)
        elif char == '\n':
            device.emit_click(uinput.KEY_ENTER)
        elif char == '.':
            device.emit_click(uinput.KEY_DOT)
        elif char == ',':
            device.emit_click(uinput.KEY_COMMA)
        elif char == '/':
            device.emit_click(uinput.KEY_SLASH)
        elif char == '\\':
            device.emit_click(uinput.KEY_BACKSLASH)
        elif char == ';':
            device.emit_click(uinput.KEY_SEMICOLON)
        elif char == "'":
            device.emit_click(uinput.KEY_APOSTROPHE)
        elif char == '`':
            device.emit_click(uinput.KEY_GRAVE)
        elif char == '-':
            device.emit_click(uinput.KEY_MINUS)
        elif char == '=':
            device.emit_click(uinput.KEY_EQUAL)
        elif char == '[':
            device.emit_click(uinput.KEY_LEFTBRACE)
        elif char == ']':
            device.emit_click(uinput.KEY_RIGHTBRACE)
        elif char.isalnum():
            device.emit_click(getattr(uinput, f'KEY_{char.upper()}'))
        else:
            logger.warning(f"Unsupported character: {char}")
        time.sleep(0.01)  # Small delay to ensure events are processed

# @uinput_setup
#
# Define a more comprehensive set of events
events = [getattr(uinput, f'KEY_{c}') for c in string.ascii_uppercase]
events += [getattr(uinput, f'KEY_{i}') for i in range(10)]
events += [
    uinput.KEY_SPACE, uinput.KEY_ENTER, uinput.KEY_BACKSPACE,
    uinput.KEY_TAB, uinput.KEY_LEFTSHIFT, uinput.KEY_RIGHTSHIFT,
    uinput.KEY_LEFTCTRL, uinput.KEY_RIGHTCTRL, uinput.KEY_LEFTALT,
    uinput.KEY_RIGHTALT, uinput.KEY_LEFTMETA, uinput.KEY_RIGHTMETA,
    uinput.KEY_DOT, uinput.KEY_COMMA, uinput.KEY_SLASH, uinput.KEY_BACKSLASH,
    uinput.KEY_SEMICOLON, uinput.KEY_APOSTROPHE, uinput.KEY_GRAVE,
    uinput.KEY_MINUS, uinput.KEY_EQUAL, uinput.KEY_LEFTBRACE, uinput.KEY_RIGHTBRACE,
]

# Create a mapping for special characters
special_char_map = {
    '!': (uinput.KEY_LEFTSHIFT, uinput.KEY_1),
    '@': (uinput.KEY_LEFTSHIFT, uinput.KEY_2),
    '#': (uinput.KEY_LEFTSHIFT, uinput.KEY_3),
    '$': (uinput.KEY_LEFTSHIFT, uinput.KEY_4),
    '%': (uinput.KEY_LEFTSHIFT, uinput.KEY_5),
    '^': (uinput.KEY_LEFTSHIFT, uinput.KEY_6),
    '&': (uinput.KEY_LEFTSHIFT, uinput.KEY_7),
    '*': (uinput.KEY_LEFTSHIFT, uinput.KEY_8),
    '(': (uinput.KEY_LEFTSHIFT, uinput.KEY_9),
    ')': (uinput.KEY_LEFTSHIFT, uinput.KEY_0),
    '_': (uinput.KEY_LEFTSHIFT, uinput.KEY_MINUS),
    '+': (uinput.KEY_LEFTSHIFT, uinput.KEY_EQUAL),
    '{': (uinput.KEY_LEFTSHIFT, uinput.KEY_LEFTBRACE),
    '}': (uinput.KEY_LEFTSHIFT, uinput.KEY_RIGHTBRACE),
    '|': (uinput.KEY_LEFTSHIFT, uinput.KEY_BACKSLASH),
    ':': (uinput.KEY_LEFTSHIFT, uinput.KEY_SEMICOLON),
    '"': (uinput.KEY_LEFTSHIFT, uinput.KEY_APOSTROPHE),
    '<': (uinput.KEY_LEFTSHIFT, uinput.KEY_COMMA),
    '>': (uinput.KEY_LEFTSHIFT, uinput.KEY_DOT),
    '?': (uinput.KEY_LEFTSHIFT, uinput.KEY_SLASH),
    '~': (uinput.KEY_LEFTSHIFT, uinput.KEY_GRAVE),
}

# @virtual_device
# Create our virtual device
try:
    device = uinput.Device(events)
    logger.info("Successfully created uinput device")
except Exception as e:
    logger.error(f"Failed to create uinput device: {e}")
    raise

# @cleanup
def cleanup():
    global transcribing, running, cleanup_done
    if cleanup_done:
        return
    cleanup_done = True
    
    logger.info("Cleaning up and shutting down...")
    transcribing = False
    running = False  # Signal all threads to stop
    
    restore_terminal()
    logger.info("Cleanup complete.")

# @restore_terminal
def restore_terminal():
    global original_terminal_settings
    if original_terminal_settings:
        logger.info("Restoring terminal settings...")
        termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, original_terminal_settings)
        logger.info("Terminal settings restored.")

# @tk_cleanup
def tk_cleanup():
    global tk_root, running
    logger.info("Tkinter cleanup initiated...")
    running = False
    if tk_root:
        tk_root.quit()
    cleanup()

# @keyboard_interrupt_monitor
def keyboard_interrupt_monitor():
    global running, original_terminal_settings
    fd = sys.stdin.fileno()
    original_terminal_settings = termios.tcgetattr(fd)

    def handle_interrupt(signum, frame):
        logger.info("Interrupt received. Initiating shutdown...")
        tk_cleanup()

    signal.signal(signal.SIGINT, handle_interrupt)

    while running:
        time.sleep(0.1)  # Short sleep to reduce CPU usage

    logger.info("Keyboard interrupt monitor exiting.")

# @TKINTER_UI
class TalkieUI:
    def __init__(self, master):
        self.master = master
        master.title("Talkie")

        # Create menu bar
        self.menu_bar = Menu(master)
        master.config(menu=self.menu_bar)

        # Create File menu
        self.file_menu = Menu(self.menu_bar, tearoff=0)
        self.menu_bar.add_cascade(label="File", menu=self.file_menu)
        self.file_menu.add_command(label="Quit", command=self.quit_app, accelerator="Alt+Q")

        # Bind Alt+Q to quit_app function
        master.bind("<Alt-q>", lambda event: self.quit_app())

        self.button = tk.Button(master, text="Start Transcription", command=self.toggle_transcription)
        self.button.pack(pady=10)

        # Audio device selection frame
        self.device_frame = tk.Frame(master)
        self.device_frame.pack(pady=5)
        
        tk.Label(self.device_frame, text="Audio Device:").pack(side=tk.LEFT)
        
        # Get available devices
        self.available_devices = get_input_devices_for_ui()
        device_names = [device[0] for device in self.available_devices]  # Display names
        
        self.device_var = tk.StringVar()
        self.device_combo = ttk.Combobox(self.device_frame, 
                                        textvariable=self.device_var,
                                        values=device_names,
                                        state="readonly",
                                        width=30)
        self.device_combo.pack(side=tk.LEFT, padx=5)
        self.device_combo.bind("<<ComboboxSelected>>", self.on_device_change)
        
        # Set current device from config
        self.set_current_device_from_config()

        # Voice threshold controls frame
        self.controls_frame = tk.Frame(master)
        self.controls_frame.pack(pady=5)
        
        # Voice threshold slider
        tk.Label(self.controls_frame, text="Voice Threshold:").pack(side=tk.LEFT)
        self.threshold_var = tk.DoubleVar(value=voice_threshold)
        self.threshold_scale = tk.Scale(self.controls_frame, from_=10, to=300, 
                                       resolution=5, orient=tk.HORIZONTAL, 
                                       variable=self.threshold_var,
                                       command=self.update_threshold)
        self.threshold_scale.pack(side=tk.LEFT, padx=5)
        
        # Audio energy display
        self.energy_label = tk.Label(self.controls_frame, text="Audio: 0.000")
        self.energy_label.pack(side=tk.LEFT, padx=10)
        
        # Second row of controls
        self.controls_frame2 = tk.Frame(master)
        self.controls_frame2.pack(pady=5)
        
        # Silence trailing duration slider
        tk.Label(self.controls_frame2, text="Silence Trailing (s):").pack(side=tk.LEFT)
        self.silence_var = tk.DoubleVar(value=silence_trailing_duration)
        self.silence_scale = tk.Scale(self.controls_frame2, from_=0.1, to=2.0, 
                                     resolution=0.1, orient=tk.HORIZONTAL, 
                                     variable=self.silence_var,
                                     command=self.update_silence_duration)
        self.silence_scale.pack(side=tk.LEFT, padx=5)
        
        # Speech timeout slider
        tk.Label(self.controls_frame2, text="Speech Timeout (s):").pack(side=tk.LEFT)
        self.timeout_var = tk.DoubleVar(value=speech_timeout)
        self.timeout_scale = tk.Scale(self.controls_frame2, from_=1.0, to=10.0, 
                                     resolution=0.5, orient=tk.HORIZONTAL, 
                                     variable=self.timeout_var,
                                     command=self.update_speech_timeout)
        self.timeout_scale.pack(side=tk.LEFT, padx=5)

        self.partial_text = scrolledtext.ScrolledText(master, wrap=tk.WORD, width=60, height=10)
        self.partial_text.pack(pady=10)
        
        # Configure tags for sent and unsent words
        self.partial_text.tag_configure("sent", foreground="gray")
        self.partial_text.tag_configure("unsent", foreground="black")

        self.status_label = tk.Label(master, text="Transcription: OFF")
        self.status_label.pack(pady=5)
        
        # Start updating audio energy display
        self.update_energy_display()

    def toggle_transcription(self):
        toggle_transcription()
        self.update_ui()

    def update_threshold(self, value):
        """Update the global voice threshold when slider changes"""
        global voice_threshold
        voice_threshold = float(value)
        update_config_param("voice_threshold", voice_threshold)
        logger.debug(f"Voice threshold updated to: {voice_threshold}")

    def update_silence_duration(self, value):
        """Update the global silence trailing duration when slider changes"""
        global silence_trailing_duration, max_silence_frames
        silence_trailing_duration = float(value)
        update_config_param("silence_trailing_duration", silence_trailing_duration)
        # Recalculate max_silence_frames based on current block duration
        max_silence_frames = int(silence_trailing_duration / BLOCK_DURATION)
        logger.debug(f"Silence trailing duration updated to: {silence_trailing_duration}s ({max_silence_frames} frames)")

    def update_speech_timeout(self, value):
        """Update the global speech timeout when slider changes"""
        global speech_timeout
        speech_timeout = float(value)
        update_config_param("speech_timeout", speech_timeout)
        logger.debug(f"Speech timeout updated to: {speech_timeout}s")

    def set_current_device_from_config(self):
        """Set the dropdown to show the current configured device"""
        try:
            config = load_config()
            current_device = config.get("audio_device", "pulse")
            
            # Find matching device in the list
            for display_name, device_id, device_name in self.available_devices:
                # Check if the config device matches by name or ID
                if (current_device.lower() in device_name.lower() or 
                    (current_device.isdigit() and int(current_device) == device_id)):
                    self.device_var.set(display_name)
                    logger.debug(f"Set UI device to: {display_name}")
                    break
            else:
                # Fallback to first device if no match found
                if self.available_devices:
                    self.device_var.set(self.available_devices[0][0])
                    logger.warning(f"Device '{current_device}' not found, using first available")
        except Exception as e:
            logger.error(f"Error setting current device from config: {e}")

    def on_device_change(self, event=None):
        """Handle audio device change from dropdown"""
        try:
            selected_display_name = self.device_var.get()
            
            # Find the selected device info
            selected_device = None
            for display_name, device_id, device_name in self.available_devices:
                if display_name == selected_display_name:
                    selected_device = (display_name, device_id, device_name)
                    break
            
            if selected_device:
                display_name, device_id, device_name = selected_device
                logger.info(f"Device changed to: {device_name} (ID: {device_id})")
                
                # Update config with device name for consistency
                update_config_param("audio_device", device_name.lower())
                
                # Show a message that restart is needed for device change
                logger.info("Device changed in config. Restart talkie to use the new device.")
                
                # Update the window title to show pending restart
                self.master.title("Talkie - Restart required for device change")
                
        except Exception as e:
            logger.error(f"Error changing audio device: {e}")

    def update_energy_display(self):
        """Update the audio energy display in real-time"""
        global current_audio_energy
        # Update energy display with color coding (show as integer for int16 audio)
        energy_text = f"Audio: {int(current_audio_energy)}"
        if current_audio_energy > voice_threshold:
            self.energy_label.config(text=energy_text, fg="green")  # Voice detected
        else:
            self.energy_label.config(text=energy_text, fg="red")    # Silence
        
        # Schedule next update
        self.master.after(100, self.update_energy_display)

    def update_ui(self):
        if transcribing:
            self.button.config(text="Stop Transcription")
            self.status_label.config(text="Transcription: ON")
        else:
            self.button.config(text="Start Transcription")
            self.status_label.config(text="Transcription: OFF")

    def update_partial_text(self, text):
        self.partial_text.delete(1.0, tk.END)
        words = text.split()
        for word in words:
            if word.startswith('<sent>') and word.endswith('</sent>'):
                self.partial_text.insert(tk.END, word[6:-7] + ' ', "sent")
            else:
                self.partial_text.insert(tk.END, word + ' ', "unsent")

    def clear_partial_text(self):
        self.partial_text.delete(1.0, tk.END)

    def quit_app(self):
        logger.info("Quit option selected. Initiating shutdown...")
        tk_cleanup()

# @engine_environment_setup
def setup_engine_environment(engine_config):
    """Setup environment variables based on selected engine configuration"""
    import os
    
    # Configure environment based on engine type
    engine_type = engine_config.get('engine_type')
    if engine_type == SpeechEngineType.SHERPA_ONNX:
        # Clean up any existing GPU environment variables for CPU-only operation
        for gpu_var in ['ORT_PROVIDERS', 'OV_DEVICE', 'OV_GPU_ENABLE_BINARY_CACHE']:
            if gpu_var in os.environ:
                del os.environ[gpu_var]
        logger.info("Configured environment for CPU-based Sherpa-ONNX")
    elif engine_type == SpeechEngineType.VOSK:
        # Vosk doesn't need special environment configuration
        logger.debug("Using Vosk engine - no special environment setup needed")

# @engine_detection  
def detect_best_engine():
    """Detect best available speech engine with Vosk preferred for accuracy"""
    logger = logging.getLogger(__name__)
    
    # Try Vosk first (preferred default for accuracy and reliability)
    try:
        import vosk
        import os
        
        # Check if the Vosk model path exists
        if os.path.exists(DEFAULT_MODEL_PATH):
            logger.info("Using Vosk engine (default)")
            return SpeechEngineType.VOSK, {
                'model_path': DEFAULT_MODEL_PATH,
                'samplerate': 16000
            }
        else:
            logger.warning(f"Vosk model not found at {DEFAULT_MODEL_PATH}")
    except ImportError:
        logger.info("Vosk not available")
    except Exception as e:
        logger.warning(f"Error checking Vosk: {e}")
    
    # Fallback to Sherpa-ONNX if Vosk unavailable
    try:
        import sherpa_onnx
        logger.info("Using Sherpa-ONNX engine as fallback")
        return SpeechEngineType.SHERPA_ONNX, {
            'model_path': 'models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26',
            'use_int8': True,
            'samplerate': 16000
        }
    except ImportError:
        logger.error("Neither Vosk nor Sherpa-ONNX available")
        return None, None

# @main
def main():
    global app, tk_root, transcribe_thread, running
    parser = argparse.ArgumentParser(description="Talkie - Speech to Text with Sherpa-ONNX")
    parser.add_argument("-d", "--device", help="Substring of audio input device name")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose (debug) output")
    parser.add_argument("-m", "--model", help="Path to Vosk model (fallback only)")
    parser.add_argument("-t", "--transcribe", action="store_true", help="Start transcription immediately")
    parser.add_argument("--engine", choices=["auto", "vosk", "sherpa-onnx"], 
                       default="auto", help="Speech engine (default: auto)")
    args = parser.parse_args()

    # Setup logging
    setup_logging(args.verbose)

    # Load configuration
    config = load_config()
    logger.info(f"Loaded configuration: {config}")

    logger.info("Talkie - Speech to Text with Sherpa-ONNX - Starting up")
    logger.info(f"Block duration: {BLOCK_DURATION} seconds")
    logger.info(f"Queue size: {QUEUE_SIZE}")

    # Determine engine configuration
    if args.engine == 'vosk':
        engine_config = {
            'engine_type': SpeechEngineType.VOSK,
            'model_path': args.model or DEFAULT_MODEL_PATH,
            'samplerate': 16000
        }
        # Check if the Vosk model path exists
        if not os.path.exists(engine_config['model_path']):
            logger.error(f"Vosk model path does not exist: {engine_config['model_path']}")
            return
    elif args.engine == 'sherpa-onnx':
        engine_config = {
            'engine_type': SpeechEngineType.SHERPA_ONNX,
            'model_path': 'models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26',
            'use_int8': True,
            'samplerate': 16000
        }
    else:  # auto
        engine_type, engine_params = detect_best_engine()
        if engine_type is None:
            logger.error("No speech engines available")
            return
        engine_config = {'engine_type': engine_type, **engine_params}

    # Setup environment variables based on engine configuration
    setup_engine_environment(engine_config)
    
    logger.info(f"Using engine: {engine_config['engine_type'].value}")
    logger.info(f"Engine config: {engine_config}")

    logger.debug("Selecting audio device")
    try:
        if args.device:
            device_id, samplerate = select_audio_device(args.device)
            # Save device choice to config if it was manually specified
            update_config_param("audio_device", args.device)
        else:
            device_id, samplerate = select_audio_device(config=config)

        if device_id is None or samplerate is None:
            logger.warning("Failed to select audio device automatically. Starting without audio - use UI dropdown to select device.")
            logger.info("Available devices: " + str([f"{i}: {d['name']}" for i, d in enumerate(sd.query_devices()) if d['max_input_channels'] > 0]))
            # Set defaults for no-audio startup
            device_id = None
            samplerate = 16000  # Default sample rate

        logger.info(f"Selected device ID: {device_id}, Sample rate: {samplerate}")
        
        # Update engine config with actual device sample rate
        engine_config['samplerate'] = samplerate
        logger.info(f"Updated engine config with device sample rate: {samplerate}")
    except Exception as e:
        logger.error(f"Error during audio device selection: {e}")
        return

    # Set initial transcription state
    # Set initial transcription state and update state file if needed
    if args.transcribe:
        # Write to state file to ensure consistency
        talkie_state_file = Path.home() / ".talkie"
        try:
            import json
            state_data = {"transcribing": True}
            with open(talkie_state_file, 'w') as f:
                json.dump(state_data, f)
            logger.info("Updated ~/.talkie state file to enable transcription")
        except Exception as e:
            logger.warning(f"Could not update state file: {e}")
    
    set_initial_transcription_state(args.transcribe)

    logger.info("Preparing to start transcription thread")
    try:
        transcribe_thread = threading.Thread(target=transcribe, args=(device_id, samplerate, BLOCK_DURATION, QUEUE_SIZE, engine_config))
        transcribe_thread.daemon = True
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

    # Start keyboard interrupt monitor thread
    keyboard_thread = threading.Thread(target=keyboard_interrupt_monitor)
    keyboard_thread.daemon = True
    keyboard_thread.start()

    logger.info(f"Transcription is {'ON' if args.transcribe else 'OFF'} by default.")
    logger.info("Press Meta+E to toggle transcription on/off (works globally).")
    logger.info("Use voice commands like 'period', 'comma', 'question mark', 'exclamation mark', 'new line', or 'new paragraph' for punctuation.")
    logger.info("Use 'delete last word' or 'undo last sentence' for editing.")
    logger.info("Use Alt+Q or File > Quit to exit the application.")

    # Create and run Tkinter UI
    logger.debug("Initializing Tkinter UI")
    tk_root = tk.Tk()
    app = TalkieUI(tk_root)
    app.update_ui()  # Set initial UI state
    
    # Set up protocol for window close event
    tk_root.protocol("WM_DELETE_WINDOW", tk_cleanup)
    
    logger.info("GUI initialized. Starting main loop.")
    
    def check_running():
        if running:
            tk_root.after(100, check_running)
        else:
            tk_root.quit()

    tk_root.after(100, check_running)
    
    try:
        tk_root.mainloop()
    except Exception as e:
        logger.error(f"Error in main loop: {e}")
    finally:
        cleanup()

    logger.info("Main loop exited. Shutting down.")

# @run
if __name__ == "__main__":
    main()
