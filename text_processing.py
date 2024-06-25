import uinput
import time
import logging
import string

# Set up logging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

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

