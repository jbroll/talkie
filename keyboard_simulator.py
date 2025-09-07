#!/home/john/src/talkie/bin/python3

import logging
import string
import time
import uinput

logger = logging.getLogger(__name__)

class KeyboardSimulator:
    """Manages keyboard input simulation via uinput"""
    
    def __init__(self):
        self.device = None
        self.special_char_map = self._create_special_char_map()
        self._initialize_device()
    
    def _create_events_list(self):
        """Create list of uinput events for device initialization"""
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
        return events
    
    def _create_special_char_map(self):
        """Create mapping for special characters requiring shift combinations"""
        return {
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
    
    def _initialize_device(self):
        """Initialize the uinput virtual device"""
        try:
            events = self._create_events_list()
            self.device = uinput.Device(events)
            logger.info("Successfully created uinput device")
        except Exception as e:
            logger.error(f"Failed to create uinput device: {e}")
            raise
    
    def type_text(self, text):
        """Type text using the virtual keyboard device"""
        if not self.device:
            logger.error("Keyboard device not initialized")
            return
        
        logger.debug(f"Typing text: {text}")
        
        for char in text:
            try:
                self._type_character(char)
                time.sleep(0.01)  # Small delay to ensure events are processed
            except Exception as e:
                logger.warning(f"Failed to type character '{char}': {e}")
    
    def _type_character(self, char):
        """Type a single character"""
        if char.isupper():
            # Uppercase letter - use shift combination
            self.device.emit_combo((uinput.KEY_LEFTSHIFT, getattr(uinput, f'KEY_{char.upper()}')))
        elif char in self.special_char_map:
            # Special character requiring shift
            self.device.emit_combo(self.special_char_map[char])
        elif char == ' ':
            self.device.emit_click(uinput.KEY_SPACE)
        elif char == '\n':
            self.device.emit_click(uinput.KEY_ENTER)
        elif char == '.':
            self.device.emit_click(uinput.KEY_DOT)
        elif char == ',':
            self.device.emit_click(uinput.KEY_COMMA)
        elif char == '/':
            self.device.emit_click(uinput.KEY_SLASH)
        elif char == '\\':
            self.device.emit_click(uinput.KEY_BACKSLASH)
        elif char == ';':
            self.device.emit_click(uinput.KEY_SEMICOLON)
        elif char == "'":
            self.device.emit_click(uinput.KEY_APOSTROPHE)
        elif char == '`':
            self.device.emit_click(uinput.KEY_GRAVE)
        elif char == '-':
            self.device.emit_click(uinput.KEY_MINUS)
        elif char == '=':
            self.device.emit_click(uinput.KEY_EQUAL)
        elif char == '[':
            self.device.emit_click(uinput.KEY_LEFTBRACE)
        elif char == ']':
            self.device.emit_click(uinput.KEY_RIGHTBRACE)
        elif char.isalnum():
            # Alphanumeric character
            self.device.emit_click(getattr(uinput, f'KEY_{char.upper()}'))
        else:
            logger.warning(f"Unsupported character: {char}")
    
    def cleanup(self):
        """Clean up the keyboard device"""
        if self.device:
            try:
                # uinput devices are automatically cleaned up, but we can explicitly close if needed
                logger.debug("Keyboard simulator cleanup")
            except Exception as e:
                logger.error(f"Error during keyboard cleanup: {e}")
    
    def __del__(self):
        """Ensure cleanup on destruction"""
        self.cleanup()