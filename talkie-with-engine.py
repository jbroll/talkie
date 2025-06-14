# @modified_transcribe_function
def transcribe(device_id, samplerate, block_duration, queue_size, model_path, engine_type="vosk"):
    global transcribing, q, speech_start_time, app, running, processing_state, number_buffer, number_mode_start_time

    print("Transcribe function started")
    logger.info("Transcribe function started")

    # Initialize speech manager with selected engine
    def handle_speech_result(result):
        if transcribing:
            if result.is_final:
                logger.info(f"Final: {result.text}")
                process_text(result.text, is_final=True)
                app.clear_partial_text()
            else:
                logger.debug(f"Partial: {result.text}")
                app.update_partial_text(result.text)

    # Convert string engine type to enum
    engine_enum = SpeechEngineType(engine_type)
    
    speech_manager = SpeechManager(
        engine_type=engine_enum,
        model_path=model_path,
        result_callback=handle_speech_result,
        samplerate=samplerate
    )
    
    if not speech_manager.initialize():
        logger.error("Failed to initialize speech engine")
        return
        
    speech_manager.start()
    
    q = queue.Queue(maxsize=queue_size)
    block_size = int(samplerate * block_duration)

    logger.info("Initializing audio stream...")
    try:
        with sd.RawInputStream(samplerate=samplerate, blocksize=block_size, 
                              device=device_id, dtype='int16', channels=1, 
                              callback=callback):
            logger.info(f"Audio stream initialized: device={device_id}, samplerate={samplerate} Hz")
            
            while running:
                if transcribing:
                    try:
                        # Check for number timeout
                        if processing_state == ProcessingState.NUMBER and number_mode_start_time:
                            if time.time() - number_mode_start_time > NUMBER_TIMEOUT:
                                logger.debug("Number timeout in main loop")
                                process_text("", is_final=True)
                        
                        # Get audio data and send to speech manager
                        data = q.get(timeout=0.1)
                        speech_manager.add_audio(data)
                        
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
    finally:
        speech_manager.cleanup()

    logger.info("Transcribe function ending")
    print("Transcribe function ending")

# @configuration_manager
class TalkieConfig:
    """Configuration manager for Talkie settings"""
    
    def __init__(self):
        self.speech_engine = "vosk"
        self.model_path = "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
        self.samplerate = 16000
        self.block_duration = 0.1
        self.queue_size = 5
        # Whisper-specific settings
        self.whisper_device = "cpu"
        self.whisper_compute_type = "int8"
        
    def get_engine_kwargs(self):
        """Get engine-specific parameters"""
        if self.speech_engine in ["whisper", "faster_whisper", "distil_whisper"]:
            return {
                "device": self.whisper_device,
                "compute_type": self.whisper_compute_type,
                "samplerate": self.samplerate
            }
        else:
            return {"samplerate": self.samplerate}
            
    def switch_to_whisper(self, model_size="base.en"):
        """Switch to Whisper engine"""
        self.speech_engine = "faster_whisper"
        self.model_path = model_size  # Can be model size or path
        
    def switch_to_vosk(self, model_path=None):
        """Switch to Vosk engine"""
        self.speech_engine = "vosk"
        if model_path:
            self.model_path = model_path

# @modified_main_function
def main():
    global running, app
    
    parser = argparse.ArgumentParser(description='Talkie - Speech to Text')
    parser.add_argument('--model', help='Path to speech model')
    parser.add_argument('--engine', choices=['vosk', 'whisper', 'faster_whisper'], 
                       default='vosk', help='Speech engine to use')
    parser.add_argument('--device', default='cpu', help='Device for Whisper (cpu/cuda)')
    parser.add_argument('--no-gui', action='store_true', help='Run without GUI')
    
    args = parser.parse_args()
    
    # Initialize configuration
    config = TalkieConfig()
    if args.model:
        config.model_path = args.model
    config.speech_engine = args.engine
    if args.engine in ["whisper", "faster_whisper"]:
        config.whisper_device = args.device
    
    try:
        # Setup virtual input device
        uinput_setup()
        
        if not args.no_gui:
            # Create and start GUI
            app = TalkieApp(config)
            app.run()
        else:
            # Command line mode
            device_id, samplerate = select_audio_device()
            if device_id is not None:
                running = True
                
                # Start hotkey listener
                hotkey_thread = threading.Thread(target=listen_for_hotkey)
                hotkey_thread.daemon = True
                hotkey_thread.start()
                
                # Start transcription
                transcribe(device_id, samplerate, config.block_duration, 
                          config.queue_size, config.model_path, config.speech_engine)
                          
    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        cleanup()

# @gui_modifications
class TalkieApp:
    """Modified GUI class with engine switching support"""
    
    def __init__(self, config: TalkieConfig):
        self.config = config
        self.root = tk.Tk()
        self.setup_gui()
        
    def setup_gui(self):
        # ... existing GUI setup ...
        
        # Add engine selection menu
        engine_menu = Menu(self.root)
        engine_submenu = Menu(engine_menu, tearoff=0)
        engine_submenu.add_command(label="Vosk", command=self.switch_to_vosk)
        engine_submenu.add_command(label="Whisper Base", command=self.switch_to_whisper_base)
        engine_submenu.add_command(label="Whisper Small", command=self.switch_to_whisper_small)
        engine_menu.add_cascade(label="Engine", menu=engine_submenu)
        
        menubar = Menu(self.root)
        menubar.add_cascade(label="Speech Engine", menu=engine_menu)
        self.root.config(menu=menubar)
        
    def switch_to_vosk(self):
        """Switch to Vosk engine"""
        self.config.switch_to_vosk()
        self.restart_transcription()
        
    def switch_to_whisper_base(self):
        """Switch to Whisper base model"""
        self.config.switch_to_whisper("base.en")
        self.restart_transcription()
        
    def switch_to_whisper_small(self):
        """Switch to Whisper small model"""
        self.config.switch_to_whisper("small.en")
        self.restart_transcription()
        
    def restart_transcription(self):
        """Restart transcription with new engine"""
        # Implementation depends on your threading setup
        # This would signal the transcription thread to restart
        pass
