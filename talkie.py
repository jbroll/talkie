#!/home/john/src/talkie/bin/python3

# @IMPORTS
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

# @constants
BLOCK_DURATION = 0.1  # in seconds
QUEUE_SIZE = 5
DEFAULT_MODEL_PATH = "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
MIN_WORD_LENGTH = 2

# @logger
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def setup_logging(verbose=False):
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

def list_audio_devices():
    logger.info("Available audio input devices:")
    devices = sd.query_devices()
    for i, device in enumerate(devices):
        if device['max_input_channels'] > 0:
            logger.info(f"{i}: {device['name']}")
    return devices

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

def listen_for_hotkey():
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    devices = {dev.fd: dev for dev in devices}
    
    meta_pressed = False
    
    while True:
        r, w, x = select(devices, [], [])
        for fd in r:
            for event in devices[fd].read():
                if event.type == evdev.ecodes.EV_KEY:
                    key_event = evdev.categorize(event)
                    
                    # Check for Meta (Super) key
                    if key_event.scancode == 125:  # Left Meta key
                        meta_pressed = key_event.keystate in (key_event.key_down, key_event.key_hold)
                    
                    # Check for 'E' key press while Meta is held down
                    if key_event.scancode == 18 and key_event.keycode == 'KEY_E':
                        if meta_pressed and key_event.keystate == key_event.key_up:
                            toggle_transcription()
                            print("Hotkey pressed. Transcription toggled.")

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

def smart_capitalize(text):
    global capitalize_next
    if capitalize_next:
        text = text.capitalize()
        capitalize_next = False
    return text

def process_text(text):
    logger.info(f"Processing text: {text}")
    global capitalize_next
    words = text.split()
    output = []
    for word in words:
        if word in punctuation:
            output.append(punctuation[word])
            if punctuation[word] in ['.', '!', '?']:
                capitalize_next = True
        else:
            processed_word = word.strip().lower()
            if len(processed_word) >= MIN_WORD_LENGTH:
                output.append(smart_capitalize(processed_word))
    
    result = ' '.join(output)
    type_text(result)
    logger.info(f"Processed and typed text: {result}")


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

# Create our virtual device
try:
    device = uinput.Device(events)
    logger.info("Successfully created uinput device")
except Exception as e:
    logger.error(f"Failed to create uinput device: {e}")
    raise

# @globals
transcribing = False
total_processing_time = 0
total_chunks_processed = 0
q = None  # Will be initialized in transcribe function
speech_start_time = None

def main():
    parser = argparse.ArgumentParser(description="Speech-to-Text System using Vosk")
    parser.add_argument("-d", "--device", help="Substring of audio input device name")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose (debug) output")
    parser.add_argument("-m", "--model", help="Path to the Vosk model", default=DEFAULT_MODEL_PATH)
    parser.add_argument("-t", "--transcribe", action="store_true", help="Start transcription immediately")
    args = parser.parse_args()

    # Setup logging
    setup_logging(args.verbose)

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

last_typed = []
capitalize_next = True
MIN_WORD_LENGTH = 2

punctuation = {
    "period": ".",
    "comma": ",",
    "question mark": "?",
    "exclamation mark": "!",
    "new line": "\n",
    "new paragraph": "\n\n"
}

# @run
if __name__ == "__main__":
    main()

