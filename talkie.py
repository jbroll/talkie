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

# @constants
BLOCK_DURATION = 0.1  # in seconds
QUEUE_SIZE = 5
DEFAULT_MODEL_PATH = "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
MIN_WORD_LENGTH = 2
MAX_NUMBER_BUFFER_SIZE = 20  # Maximum number of words to buffer for number conversion

# @globals
transcribing = False
total_processing_time = 0
total_chunks_processed = 0
q = None  # Will be initialized in transcribe function
speech_start_time = None

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

# @listen_for_hotkey
def listen_for_hotkey():
    global running
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    devices = {dev.fd: dev for dev in devices}
    
    meta_pressed = False
    
    while running:
        r, w, x = select(devices, [], [], 1)  # 1 second timeout
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
                            logger.info("Hotkey pressed. Transcription toggled.")
    logger.info("Hotkey listener thread exiting.")

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
    global capitalize_next
    words = text.split()
    output = []
    number_buffer = []

    def process_number_buffer():
        if number_buffer:
            try:
                number_phrase = ' '.join(number_buffer)
                number = w2n.word_to_num(number_phrase)
                output.append(str(number))
                logger.debug(f"Converted number buffer to: {number}")
                return True
            except ValueError:
                logger.debug(f"Failed to convert number buffer: {' '.join(number_buffer)}")
                return False
        return True

    for word in words:
        if word.lower() in ['and', 'point']:
            number_buffer.append(word.lower())
        elif word in punctuation:
            if not process_number_buffer():
                output.extend([smart_capitalize(w) for w in number_buffer])
            number_buffer.clear()
            if is_final:  # Only add punctuation for final results
                output.append(punctuation[word])
                if punctuation[word] in ['.', '!', '?']:
                    capitalize_next = True
        else:
            processed_word = word.strip().lower()
            try:
                # Try to convert the word to a number to check if it's a number word
                w2n.word_to_num(processed_word)
                number_buffer.append(processed_word)
            except ValueError:
                # If it's not a number word, process the number buffer
                if not process_number_buffer():
                    output.extend([smart_capitalize(w) for w in number_buffer])
                number_buffer.clear()
                output.append(smart_capitalize(processed_word))

    # Process any remaining words in the number buffer
    if number_buffer:
        if not process_number_buffer():
            output.extend([smart_capitalize(w) for w in number_buffer])

    result = ' '.join(output)
    if is_final:
        result = result.strip()
        if not result.endswith(('.', '!', '?')):
            result += '.'  # Add a period at the end of final results if no punctuation

    type_text(result + (' ' if not is_final else ''))
    logger.info(f"Processed and typed text: {result}")

# @set_initial_transcription_state
def set_initial_transcription_state(state):
    global transcribing
    transcribing = state
    logger.info(f"Initial transcription state set to: {'ON' if transcribing else 'OFF'}")

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

# @toggle_transcription
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
    
    # Update UI if it exists
    if 'app' in globals():
        app.update_ui()

# @transcribe
def transcribe(device_id, samplerate, block_duration, queue_size, model_path):
    global transcribing, q, speech_start_time, app, running

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
                else:
                    logger.debug("Transcription is off, waiting")
                    time.sleep(0.1)
    except Exception as e:
        logger.error(f"Error in audio stream: {e}")
        print(f"Error in audio stream: {e}")

    logger.info("Transcribe function ending")
    print("Transcribe function ending")

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

# @main
def main():
    global app, tk_root, transcribe_thread, hotkey_thread, running
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

    logger.debug("Starting hotkey listener thread")
    # Start hotkey listener thread
    hotkey_thread = threading.Thread(target=listen_for_hotkey)
    hotkey_thread.daemon = True
    hotkey_thread.start()

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