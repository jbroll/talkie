#!/home/john/src/talkie/bin/python3

import logging
import time
from enum import Enum
from word2number import w2n

logger = logging.getLogger(__name__)

# Processing state enumeration
class ProcessingState(Enum):
    NORMAL = "normal"
    NUMBER = "number"

# Punctuation mapping
PUNCTUATION_MAP = {
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

class TextProcessor:
    """Handles speech-to-text processing, state management, and text formatting"""
    
    def __init__(self, min_word_length=2, max_number_buffer_size=20, number_timeout=2.0):
        self.min_word_length = min_word_length
        self.max_number_buffer_size = max_number_buffer_size
        self.number_timeout = number_timeout
        
        # State management
        self.capitalize_next = True
        self.processing_state = ProcessingState.NORMAL
        self.number_buffer = []
        self.number_mode_start_time = None
        self.last_word_time = None
        self.last_utterance_completed = False
        
        # Callbacks
        self.text_output_callback = None
    
    def set_text_output_callback(self, callback):
        """Set callback function for text output"""
        self.text_output_callback = callback
    
    def smart_capitalize(self, text):
        """Apply smart capitalization based on sentence context"""
        if self.capitalize_next:
            text = text.capitalize()
            self.capitalize_next = False
        return text
    
    def is_number_word(self, word):
        """Check if a word can be converted to a number"""
        try:
            w2n.word_to_num(word.lower())
            return True
        except ValueError:
            return False
    
    def process_number_buffer(self):
        """Process accumulated number buffer and return success status"""
        if not self.number_buffer:
            return True
        
        try:
            number_phrase = ' '.join(self.number_buffer)
            number = w2n.word_to_num(number_phrase)
            result = str(number)
            logger.debug(f"Converted number buffer to: {number}")
            success = True
        except ValueError:
            # Failed to convert - output words as-is
            logger.debug(f"Failed to convert number buffer: {' '.join(self.number_buffer)}")
            result = ' '.join([self.smart_capitalize(w) for w in self.number_buffer])
            success = False
        
        # Reset state
        self.number_buffer.clear()
        self.processing_state = ProcessingState.NORMAL
        self.number_mode_start_time = None
        
        return result, success
    
    def check_number_timeout(self):
        """Check if number mode has timed out"""
        current_time = time.time()
        if (self.processing_state == ProcessingState.NUMBER and 
            self.number_mode_start_time and 
            current_time - self.number_mode_start_time > self.number_timeout):
            logger.debug("Number mode timed out")
            return True
        return False
    
    def process_text(self, text, is_final=False):
        """Process speech text with state management, number conversion, and punctuation"""
        logger.info(f"Processing text: {text}")

        # Only process final results for output - partial results are just for UI display
        if not is_final:
            logger.debug("Skipping processing for partial result")
            return

        words = text.split()
        output = []
        current_time = time.time()
        
        # Add space at beginning of new utterance if we just completed a previous utterance
        add_leading_space = False
        if self.last_utterance_completed and len(words) > 0:
            add_leading_space = True
            self.last_utterance_completed = False
            logger.debug("Adding leading space for new utterance")
        
        # Check for timeout before processing new words
        if self.check_number_timeout():
            if self.number_buffer:
                result, _ = self.process_number_buffer()
                output.append(result)
        
        for i, word in enumerate(words):
            word_lower = word.lower()
            self.last_word_time = current_time
            
            # Handle based on current state
            if self.processing_state == ProcessingState.NORMAL:
                # In NORMAL state
                if self.is_number_word(word_lower):
                    # Transition to NUMBER state
                    self.processing_state = ProcessingState.NUMBER
                    self.number_mode_start_time = current_time
                    self.number_buffer = [word_lower]
                    logger.debug(f"Entering NUMBER state with: {word_lower}")
                elif word_lower == "point" and i + 1 < len(words) and self.is_number_word(words[i + 1].lower()):
                    # Look-ahead for "point" followed by number
                    self.processing_state = ProcessingState.NUMBER
                    self.number_mode_start_time = current_time
                    self.number_buffer = [word_lower]
                    logger.debug("Entering NUMBER state with 'point'")
                elif word_lower in PUNCTUATION_MAP:
                    # Handle punctuation
                    if is_final:  # Only add punctuation for final results
                        punct = PUNCTUATION_MAP[word_lower]
                        output.append(punct)
                        if punct in ['.', '!', '?']:
                            self.capitalize_next = True
                else:
                    # Regular word
                    output.append(self.smart_capitalize(word))
            
            else:  # ProcessingState.NUMBER
                # In NUMBER state
                if self.is_number_word(word_lower):
                    # Continue collecting number words
                    if len(self.number_buffer) < self.max_number_buffer_size:
                        self.number_buffer.append(word_lower)
                        logger.debug(f"Added to number buffer: {word_lower}")
                    else:
                        # Buffer full - process and start new
                        result, _ = self.process_number_buffer()
                        output.append(result)
                        self.processing_state = ProcessingState.NUMBER
                        self.number_mode_start_time = current_time
                        self.number_buffer = [word_lower]
                elif word_lower == "and" and len(self.number_buffer) > 0:
                    # "and" is valid in number context
                    if len(self.number_buffer) < self.max_number_buffer_size:
                        self.number_buffer.append(word_lower)
                        logger.debug("Added 'and' to number buffer")
                elif word_lower == "point":
                    # "point" is valid in number context
                    if len(self.number_buffer) < self.max_number_buffer_size:
                        self.number_buffer.append(word_lower)
                        logger.debug("Added 'point' to number buffer")
                elif word_lower in PUNCTUATION_MAP:
                    # Punctuation ends number mode
                    result, _ = self.process_number_buffer()
                    output.append(result)
                    if is_final:
                        punct = PUNCTUATION_MAP[word_lower]
                        output.append(punct)
                        if punct in ['.', '!', '?']:
                            self.capitalize_next = True
                else:
                    # Non-number word ends number mode
                    result, _ = self.process_number_buffer()
                    output.append(result)
                    output.append(self.smart_capitalize(word))
        
        # Handle any remaining buffer at the end
        if is_final and self.number_buffer:
            result, _ = self.process_number_buffer()
            output.append(result)
        
        # Only check timeout if we're still collecting numbers and this is a partial result
        elif not is_final and self.processing_state == ProcessingState.NUMBER:
            # Keep the buffer for next partial/final result
            pass
        
        result = ' '.join(output)
        if is_final:
            result = result.strip()
        
        if result:  # Only output if there's something to output
            # Add leading space for new utterance if needed
            if add_leading_space:
                result = ' ' + result
            
            final_text = result + (' ' if not is_final else '')
            
            # Send to output callback if available
            if self.text_output_callback:
                self.text_output_callback(final_text)
            
            logger.info(f"Processed text: {result}")
        elif add_leading_space:
            # Even if no words, we might need to add just a space for separation
            if self.text_output_callback:
                self.text_output_callback(' ')
            logger.debug("Output leading space for utterance separation")
        
        if is_final:
            self.last_utterance_completed = True
        
        return result
    
    def force_number_timeout(self):
        """Force process any pending number buffer due to timeout"""
        if self.processing_state == ProcessingState.NUMBER and self.number_buffer:
            logger.debug("Forcing number buffer processing due to timeout")
            result, _ = self.process_number_buffer()
            if result and self.text_output_callback:
                self.text_output_callback(result + ' ')
            return result
        return None
    
    def reset_state(self):
        """Reset processing state (useful when transcription stops)"""
        if self.processing_state == ProcessingState.NUMBER:
            self.processing_state = ProcessingState.NORMAL
            self.number_buffer.clear()
            self.number_mode_start_time = None
        self.last_utterance_completed = False
        logger.debug("Text processor state reset")