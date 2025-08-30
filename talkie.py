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
from pathlib import Path

from JSONFileMonitor import JSONFileMonitor
from speech.speech_engine import SpeechManager, SpeechEngineType, SpeechResult
from speech.OpenVINO_Whisper_engine import detect_intel_npu, check_npu_requirements

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

# @callback
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

    print("Transcribe function started")
    logger.info("Transcribe function started")

    # Initialize speech manager with selected engine
    def handle_speech_result(result: SpeechResult):
        if transcribing:
            if result.is_final:
                logger.info(f"Final: {result.text}")
                process_text(result.text, is_final=True)
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
        
        # Try fallback to Vosk if faster-whisper or OpenVINO failed
        if engine_type in [SpeechEngineType.FASTER_WHISPER, SpeechEngineType.OPENVINO_WHISPER]:
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

    logger.info("Initializing audio stream...")
    try:
        with sd.RawInputStream(samplerate=samplerate, blocksize=block_size, 
                              device=device_id, dtype='int16', channels=1, 
                              callback=callback):
            logger.info(f"Audio stream initialized: device={device_id}, samplerate={samplerate} Hz")
            
            while running:
                if transcribing:
                    try:
                        # Handle number timeout
                        if processing_state == ProcessingState.NUMBER and number_mode_start_time:
                            if time.time() - number_mode_start_time > NUMBER_TIMEOUT:
                                logger.debug("Number timeout in main loop")
                                process_text("", is_final=True)
                        
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
                else:
                    # Reset logic when transcription is off
                    if processing_state == ProcessingState.NUMBER:
                        processing_state = ProcessingState.NORMAL
                        number_buffer.clear()
                        number_mode_start_time = None
                    time.sleep(0.1)
                    
    except Exception as e:
        logger.error(f"Error in audio stream: {e}")
        print(f"Error in audio stream: {e}")
    finally:
        if speech_manager:
            speech_manager.cleanup()
        file_monitor.stop()
    
    logger.info("Transcribe function ending")
    print("Transcribe function ending")

# @list_audio_devices
def list_audio_devices():
    logger.info("Available audio input devices:")
    devices = sd.query_devices()
    for i, device in enumerate(devices):
        if device['max_input_channels'] > 0:
            logger.info(f"{i}: {device['name']}")
    return devices

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
def select_audio_device(device_substring=None):
    devices = list_audio_devices()
    
    if device_substring:
        matching_devices = [
            (i, device) for i, device in enumerate(devices)
            if device['max_input_channels'] > 0 and device_substring.lower() in device['name'].lower()
        ]
        
        if matching_devices:
            if len(matching_devices) > 1:
                logger.info("Multiple matching devices found:")
                for i, device in matching_devices:
                    logger.info(f"{i}: {device['name']}")
                device_id = int(input("Enter the number of the input device you want to use: "))
            else:
                device_id = matching_devices[0][0]
            
            device_info = devices[device_id]
            logger.info(f"Selected device: {device_info['name']}")
        else:
            logger.error(f"No device matching '{device_substring}' found.")
            return None, None
    else:
        while True:
            try:
                device_id = int(input("Enter the number of the input device you want to use: "))
                device_info = devices[device_id]
                if device_info['max_input_channels'] > 0:
                    break
                else:
                    logger.error("Invalid input device. Please choose a device with input channels.")
            except (ValueError, IndexError):
                logger.error("Invalid input. Please enter a valid device number.")
    
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

        self.partial_text = scrolledtext.ScrolledText(master, wrap=tk.WORD, width=60, height=10)
        self.partial_text.pack(pady=10)
        
        # Configure tags for sent and unsent words
        self.partial_text.tag_configure("sent", foreground="gray")
        self.partial_text.tag_configure("unsent", foreground="black")

        self.status_label = tk.Label(master, text="Transcription: OFF")
        self.status_label.pack(pady=5)

    def toggle_transcription(self):
        toggle_transcription()
        self.update_ui()

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

# @engine_detection  
def detect_best_engine():
    """Detect best available speech engine with faster-whisper preferred"""
    logger = logging.getLogger(__name__)
    
    # Try faster-whisper first (best accuracy + GPU/NPU support)
    try:
        import torch
        from faster_whisper import WhisperModel
        
        # Check for GPU availability
        if torch.cuda.is_available():
            gpu_name = torch.cuda.get_device_name()
            logger.info(f"CUDA GPU detected: {gpu_name} - using faster-whisper with GPU")
            return SpeechEngineType.FASTER_WHISPER, {
                'model_path': 'base',  # Good balance of speed/accuracy
                'device': 'auto',  # Will select GPU
                'compute_type': 'auto',
                'samplerate': 16000
            }
        else:
            logger.info("No GPU detected - using faster-whisper with CPU")
            return SpeechEngineType.FASTER_WHISPER, {
                'model_path': 'tiny',  # Faster on CPU
                'device': 'cpu',
                'compute_type': 'int8',
                'samplerate': 16000
            }
            
    except ImportError:
        logger.info("faster-whisper not available")
    except Exception as e:
        logger.warning(f"Error checking faster-whisper: {e}")
    
    # Fallback to Vosk (reliable CPU-based option)
    logger.info("Using Vosk engine as fallback")
    return SpeechEngineType.VOSK, {
        'model_path': DEFAULT_MODEL_PATH,
        'samplerate': 16000
    }

# @main
def main():
    global app, tk_root, transcribe_thread, running
    parser = argparse.ArgumentParser(description="Talkie - Speech to Text with OpenVINO Whisper")
    parser.add_argument("-d", "--device", help="Substring of audio input device name")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose (debug) output")
    parser.add_argument("-m", "--model", help="Path to Vosk model (fallback only)")
    parser.add_argument("-t", "--transcribe", action="store_true", help="Start transcription immediately")
    parser.add_argument("--whisper-model", default="openai/whisper-base", 
                       help="OpenVINO Whisper model name (default: openai/whisper-base)")
    parser.add_argument("--engine", choices=["auto", "faster-whisper", "vosk", "openvino"], 
                       default="auto", help="Force specific engine (default: auto)")
    parser.add_argument("--ov-device", default="AUTO",
                       help="OpenVINO device (NPU, GPU, CPU, AUTO) (default: AUTO)")
    args = parser.parse_args()

    # Setup logging
    setup_logging(args.verbose)

    logger.info("Talkie - Speech to Text with OpenVINO Whisper - Starting up")
    logger.info(f"Block duration: {BLOCK_DURATION} seconds")
    logger.info(f"Queue size: {QUEUE_SIZE}")

    # Determine engine configuration
    if args.engine == 'faster-whisper':
        engine_config = {
            'engine_type': SpeechEngineType.FASTER_WHISPER,
            'model_path': 'base',  # Good default model
            'device': 'auto',
            'compute_type': 'auto',
            'samplerate': 16000
        }
    elif args.engine == 'vosk':
        engine_config = {
            'engine_type': SpeechEngineType.VOSK,
            'model_path': args.model or DEFAULT_MODEL_PATH,
            'samplerate': 16000
        }
        # Check if the Vosk model path exists
        if not os.path.exists(engine_config['model_path']):
            logger.error(f"Vosk model path does not exist: {engine_config['model_path']}")
            return
    elif args.engine == 'openvino':
        engine_config = {
            'engine_type': SpeechEngineType.OPENVINO_WHISPER,
            'model_path': args.whisper_model,
            'device': args.ov_device,
            'samplerate': 16000
        }
    else:  # auto
        engine_type, engine_params = detect_best_engine()
        engine_config = {'engine_type': engine_type, **engine_params}

    logger.info(f"Using engine: {engine_config['engine_type'].value}")
    logger.info(f"Engine config: {engine_config}")

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
