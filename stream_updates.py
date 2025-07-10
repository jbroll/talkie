# @constants
BLOCK_DURATION = 0.1  # in seconds
QUEUE_SIZE = 5
DEFAULT_MODEL_PATH = "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
MIN_WORD_LENGTH = 2
MAX_NUMBER_BUFFER_SIZE = 20  # Maximum number of words to buffer for number conversion
NUMBER_TIMEOUT = 2.0  # Seconds to wait before processing number buffer
BUFFER_SIZE = 5  # Maximum unsent words to buffer for streaming

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

# Streaming state variables
sent_word_count = 0  # How many words from start of current partial we've sent
last_partial_words = []  # Full word list from previous partial for comparison

# @transcribe
def transcribe(device_id, samplerate, block_duration, queue_size, model_path):
    global transcribing, q, speech_start_time, app, running, processing_state, number_buffer, number_mode_start_time
    global sent_word_count, last_partial_words

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
                                process_text("", is_final=True)
                        
                        data = q.get(timeout=0.1)
                        if rec.AcceptWaveform(data):
                            result = json.loads(rec.Result())
                            if result.get('text'):
                                final_text = result['text']
                                logger.info(f"Final: {final_text}")
                                
                                # Send any remaining buffered words with number processing
                                final_words = final_text.split()
                                if len(final_words) > sent_word_count:
                                    remaining_text = ' '.join(final_words[sent_word_count:])
                                    if remaining_text:
                                        process_text(remaining_text, is_final=True)
                                
                                # Reset streaming state for next utterance
                                app.clear_partial_text()
                                sent_word_count = 0
                                last_partial_words = []
                        else:
                            partial = json.loads(rec.PartialResult())
                            if partial.get('partial'):
                                new_partial = partial['partial']
                                new_words = new_partial.split()
                                
                                logger.debug(f"Partial: {new_partial}")
                                
                                # Check for revisions in already-sent portion
                                if sent_word_count > 0 and len(last_partial_words) >= sent_word_count:
                                    if len(new_words) >= sent_word_count:
                                        sent_portion_new = new_words[:sent_word_count]
                                        sent_portion_old = last_partial_words[:sent_word_count]
                                        if sent_portion_new != sent_portion_old:
                                            print(f"WARNING: Vosk revised already-sent text: {' '.join(sent_portion_old)} -> {' '.join(sent_portion_new)}")
                                            logger.warning(f"Vosk revised already-sent text")
                                
                                # Handle partial getting shorter
                                if len(new_words) < sent_word_count:
                                    words_lost = sent_word_count - len(new_words)
                                    if words_lost > BUFFER_SIZE:
                                        print(f"ERROR: Partial shortened by {words_lost} words (more than buffer size {BUFFER_SIZE})")
                                        logger.error(f"Partial shortened by {words_lost} words")
                                        # Recover by adjusting sent_word_count
                                        sent_word_count = len(new_words)
                                    else:
                                        logger.debug(f"Partial shortened by {words_lost} words (within buffer tolerance)")
                                
                                # Calculate what's available to send
                                if len(new_words) > sent_word_count:
                                    unsent_words = new_words[sent_word_count:]
                                    words_to_send_count = max(0, len(unsent_words) - BUFFER_SIZE)
                                    
                                    if words_to_send_count > 0:
                                        words_to_send = unsent_words[:words_to_send_count]
                                        text_to_send = ' '.join(words_to_send)
                                        logger.debug(f"Sending {words_to_send_count} words: {text_to_send}")
                                        process_text(text_to_send, is_final=False)
                                        sent_word_count += words_to_send_count
                                
                                # Update display - mark sent words
                                display_words = []
                                for i, word in enumerate(new_words):
                                    if i < sent_word_count:
                                        display_words.append(f"<sent>{word}</sent>")
                                    else:
                                        display_words.append(word)
                                app.update_partial_text(' '.join(display_words))
                                
                                last_partial_words = new_words
                                
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
                    # Reset streaming state
                    sent_word_count = 0
                    last_partial_words = []
                    time.sleep(0.1)
    except Exception as e:
        logger.error(f"Error in audio stream: {e}")
        print(f"Error in audio stream: {e}")

    logger.info("Transcribe function ending")
    print("Transcribe function ending")