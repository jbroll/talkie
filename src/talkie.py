#!/home/john/src/talkie/bin/python3

import argparse
import logging
import os
import queue
import signal
import sounddevice as sd
import sys
import threading
import time
import tkinter as tk
from pathlib import Path

# Import our modular components
from audio_manager import AudioManager
from config_manager import ConfigManager
from gui_manager import TalkieGUI
from keyboard_simulator import KeyboardSimulator
from speech.speech_engine import SpeechManager, SpeechEngineType, SpeechResult
from text_processor import TextProcessor

# Constants
BLOCK_DURATION = 0.1
QUEUE_SIZE = 5
DEFAULT_MODEL_PATH = "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"

# Global state
running = True
tk_root = None

logger = logging.getLogger(__name__)

def setup_logging(verbose=False):
    """Configure logging based on verbosity level"""
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

def setup_engine_environment(engine_config):
    """Setup environment variables based on selected engine configuration"""
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

def detect_best_engine(config=None):
    """Detect best available speech engine with Vosk preferred for accuracy"""
    # Try Vosk first (preferred default for accuracy and reliability)
    try:
        import vosk
        
        # Check if the Vosk model path exists
        if os.path.exists(DEFAULT_MODEL_PATH):
            logger.info("Using Vosk engine (default)")
            vosk_params = {
                'model_path': DEFAULT_MODEL_PATH,
                'samplerate': 16000
            }
            # Add Vosk parameters if config is provided
            if config:
                vosk_params.update({
                    'max_alternatives': config.get('vosk_max_alternatives', 0),
                    'beam': config.get('vosk_beam', 20),
                    'lattice_beam': config.get('vosk_lattice_beam', 8),
                    'confidence_threshold': config.get('confidence_threshold', 280.0)
                })
            return SpeechEngineType.VOSK, vosk_params
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

class TalkieApplication:
    """Main application class that coordinates all components"""
    
    def __init__(self, args):
        self.args = args
        
        # Initialize components
        self.config_manager = ConfigManager()
        self.audio_manager = None
        self.text_processor = None
        self.keyboard_simulator = None
        self.gui = None
        self.speech_manager = None
        
        # Threading
        self.transcribe_thread = None
        self.keyboard_thread = None
        
        # Current speech confidence for UI display
        self.current_confidence = 0.0
        
        # Load initial configuration
        self.config = self.config_manager.load_config()
    
    def initialize_components(self):
        """Initialize all application components"""
        # Initialize keyboard simulator
        self.keyboard_simulator = KeyboardSimulator()
        
        # Initialize text processor with keyboard output
        self.text_processor = TextProcessor()
        self.text_processor.set_text_output_callback(self.keyboard_simulator.type_text)
        
        # Initialize audio manager with config values
        self.audio_manager = AudioManager(
            energy_threshold=self.config.get("energy_threshold", 50.0),
            lookback_duration=self.config.get("lookback_duration", 1.0),
            silence_duration=self.config.get("silence_duration", 2.0)
        )
        
    
    def determine_engine_config(self):
        """Determine speech engine configuration based on arguments"""
        if self.args.engine == 'vosk':
            engine_config = {
                'engine_type': SpeechEngineType.VOSK,
                'model_path': self.args.model or DEFAULT_MODEL_PATH,
                'samplerate': 16000,
                'max_alternatives': self.config.get('vosk_max_alternatives', 0),
                'beam': self.config.get('vosk_beam', 20),
                'lattice_beam': self.config.get('vosk_lattice_beam', 8),
                'confidence_threshold': self.config.get('confidence_threshold', 280.0)
            }
            # Check if the Vosk model path exists
            if not os.path.exists(engine_config['model_path']):
                logger.error(f"Vosk model path does not exist: {engine_config['model_path']}")
                return None
        elif self.args.engine == 'sherpa-onnx':
            engine_config = {
                'engine_type': SpeechEngineType.SHERPA_ONNX,
                'model_path': 'models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26',
                'use_int8': True,
                'samplerate': 16000
            }
        else:  # auto
            engine_type, engine_params = detect_best_engine(self.config)
            if engine_type is None:
                logger.error("No speech engines available")
                return None
            engine_config = {'engine_type': engine_type, **engine_params}
        
        return engine_config
    
    def setup_audio_device(self):
        """Setup audio device based on arguments and configuration"""
        try:
            if self.args.device:
                device_id, samplerate = self.audio_manager.select_audio_device(self.args.device)
                # Save device choice to config if it was manually specified
                self.config_manager.update_config_param("audio_device", self.args.device)
            else:
                device_id, samplerate = self.audio_manager.select_audio_device(config=self.config)

            if device_id is None or samplerate is None:
                logger.warning("Failed to select audio device automatically. Starting without audio - use UI dropdown to select device.")
                logger.info("Available devices: " + str([f"{i}: {d['name']}" for i, d in enumerate(sd.query_devices()) if d['max_input_channels'] > 0]))
                # Set defaults for no-audio startup
                device_id = None
                samplerate = 16000  # Default sample rate

            logger.info(f"Selected device ID: {device_id}, Sample rate: {samplerate}")
            return device_id, samplerate
            
        except Exception as e:
            logger.error(f"Error during audio device selection: {e}")
            return None, None
    
    def handle_speech_result(self, result: SpeechResult):
        """Handle speech recognition results"""
        if self.audio_manager.transcribing:
            # Update current confidence for UI display
            self.current_confidence = result.confidence
            
            current_energy = self.audio_manager.current_audio_energy
            if result.is_final:
                print(f"FINAL RESULT: '{result.text}' (confidence={result.confidence:.2f}, energy={current_energy:.1f})")
                self.text_processor.process_text(result.text, is_final=True)
                if self.gui:
                    self.gui.add_final_result(result.text)  # Add to final results buffer
                    self.gui.clear_partial_text()
            else:
                print(f"PARTIAL RESULT: '{result.text}' (confidence={result.confidence:.2f}, energy={current_energy:.1f})")
                if self.gui:
                    self.gui.update_partial_text(result.text)
    
    def on_file_change(self, state):
        """Handle transcription state changes from file monitor"""
        self.audio_manager.set_transcribing(state.transcribing)
    
    
    def run_main_loop(self):
        """Main processing loop that handles audio data and timeouts"""
        global running
        
        while running:
            if self.audio_manager.transcribing:
                try:
                    # Handle number timeout
                    if self.text_processor.check_number_timeout():
                        self.text_processor.force_number_timeout()
                    
                    
                    # Get audio data and process directly
                    data = self.audio_manager.q.get(timeout=0.1)
                    # Debug: track audio processing 
                    current_energy = self.audio_manager.current_audio_energy
                    qsize = self.audio_manager.q.qsize()
                    print(f"PROCESSING: energy={current_energy:.1f}, qsize={qsize}")
                    result = self.speech_manager.adapter.process_audio(data)
                    if result:
                        self.handle_speech_result(result)
                    
                except queue.Empty:
                    # Handle timeout logic
                    if self.text_processor.check_number_timeout():
                        self.text_processor.force_number_timeout()
                        
            else:
                # Reset logic when transcription is off
                self.text_processor.reset_state()
                time.sleep(0.1)
    
    def transcribe(self, device_id, samplerate, engine_config):
        """Main transcription function - runs in separate thread"""
        logger.info("Transcribe function started")
        
        # Audio manager is now simplified - no silence duration configuration needed
        
        # Create speech manager with selected engine
        engine_type = engine_config.pop('engine_type')
        self.speech_manager = SpeechManager(
            engine_type=engine_type,
            result_callback=self.handle_speech_result,
            **engine_config
        )
        
        if not self.speech_manager.initialize():
            logger.error(f"Failed to initialize {engine_type.value} engine")
            
            # Try fallback to Vosk if sherpa-onnx failed
            if engine_type == SpeechEngineType.SHERPA_ONNX:
                logger.info("Attempting fallback to Vosk engine...")
                self.speech_manager = SpeechManager(
                    engine_type=SpeechEngineType.VOSK,
                    result_callback=self.handle_speech_result,
                    model_path=DEFAULT_MODEL_PATH,
                    samplerate=samplerate  # Use actual device sample rate
                )
                
                if not self.speech_manager.initialize():
                    logger.error("Failed to initialize Vosk fallback engine")
                    return
                else:
                    logger.info("Successfully fell back to Vosk engine")
            else:
                return
        
        # Initialize audio queue and processing
        self.audio_manager.initialize_queue(QUEUE_SIZE)
        block_size = int(samplerate * BLOCK_DURATION)

        # Set audio parameters for buffer calculations
        self.audio_manager.set_audio_params(samplerate, BLOCK_DURATION)

        # Setup file monitor
        self.audio_manager.setup_file_monitor(self.on_file_change)

        if device_id is not None:
            logger.info("Initializing audio stream...")
            try:
                with sd.InputStream(samplerate=samplerate, blocksize=block_size, 
                                   device=device_id, dtype='int16', channels=1, 
                                   callback=self.audio_manager.audio_callback):
                    logger.info(f"Audio stream initialized: device={device_id}, samplerate={samplerate} Hz")
                    
                    # Run the main processing loop
                    self.run_main_loop()
                    
            except Exception as e:
                logger.error(f"Error in audio stream: {e}")
                print(f"Error in audio stream: {e}")
            finally:
                if self.speech_manager:
                    self.speech_manager.cleanup()
                self.audio_manager.cleanup_file_monitor()
        else:
            logger.info("No audio device configured. Starting without audio stream - use UI to select device.")
            # Run without audio stream - just the UI and file monitor
            try:
                # Run the main processing loop without audio
                self.run_main_loop()
            finally:
                if self.speech_manager:
                    self.speech_manager.cleanup()
                self.audio_manager.cleanup_file_monitor()
    
    def start_transcription_thread(self, device_id, samplerate, engine_config):
        """Start the transcription thread"""
        try:
            self.transcribe_thread = threading.Thread(
                target=self.transcribe, 
                args=(device_id, samplerate, engine_config)
            )
            self.transcribe_thread.daemon = True
            logger.info("Transcription thread created")
            
            self.transcribe_thread.start()
            logger.info("Transcription thread started successfully")
            
            if self.transcribe_thread.is_alive():
                logger.info("Transcription thread is running")
            else:
                logger.error("Transcription thread is not running")
                return False
                
            return True
        except Exception as e:
            logger.error(f"Failed to start transcription thread: {e}")
            return False
    
    def setup_gui(self):
        """Setup the GUI interface"""
        global tk_root
        
        logger.debug("Initializing Tkinter UI")
        tk_root = tk.Tk()
        self.gui = TalkieGUI(tk_root, self.audio_manager, self.config_manager, self.text_processor, self)
        self.gui.set_quit_callback(self.tk_cleanup)
        self.gui.update_ui()  # Set initial UI state
        
        # Set up callback to clear partial text when speech ends
        self.audio_manager.set_speech_end_callback(self.gui.clear_partial_text)
        
        return True
    
    def run_gui(self):
        """Run the GUI main loop"""
        global running
        
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
            logger.error(f"Error in GUI main loop: {e}")
        finally:
            logger.info("GUI main loop exited")
            if self.audio_manager:
                self.audio_manager.set_transcribing(False)
    
    def tk_cleanup(self):
        """Handle Tkinter cleanup"""
        global tk_root, running
        logger.info("Application closing...")
        running = False
        if self.audio_manager:
            self.audio_manager.set_transcribing(False)
        if tk_root:
            tk_root.quit()
        sys.exit(0)
    
    def run(self):
        """Main application entry point"""
        logger.info("Talkie - Speech to Text with Sherpa-ONNX - Starting up")
        logger.info(f"Block duration: {BLOCK_DURATION} seconds")
        logger.info(f"Queue size: {QUEUE_SIZE}")

        # Initialize components
        self.initialize_components()

        # Determine engine configuration
        engine_config = self.determine_engine_config()
        if engine_config is None:
            return 1

        # Setup environment variables
        setup_engine_environment(engine_config)
        
        logger.info(f"Using engine: {engine_config['engine_type'].value}")
        logger.info(f"Engine config: {engine_config}")

        # Setup audio device
        device_id, samplerate = self.setup_audio_device()
        if device_id is None and samplerate is None:
            return 1

        # Update engine config with actual device sample rate
        engine_config['samplerate'] = samplerate
        logger.info(f"Updated engine config with device sample rate: {samplerate}")

        # Set initial transcription state and update state file if needed
        if self.args.transcribe:
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
        
        self.audio_manager.set_transcribing(self.args.transcribe)

        # Start transcription thread
        if not self.start_transcription_thread(device_id, samplerate, engine_config):
            return 1

        # Simple signal handler for Ctrl+C
        def signal_handler(signum, frame):
            logger.info("Interrupt received. Stopping transcription and exiting...")
            if self.audio_manager:
                self.audio_manager.set_transcribing(False)
            sys.exit(0)
        
        signal.signal(signal.SIGINT, signal_handler)

        logger.info(f"Transcription is {'ON' if self.args.transcribe else 'OFF'} by default.")
        logger.info("Press Meta+E to toggle transcription on/off (works globally).")
        logger.info("Use voice commands like 'period', 'comma', 'question mark', 'exclamation mark', 'new line', or 'new paragraph' for punctuation.")
        logger.info("Use Alt+Q or File > Quit to exit the application.")

        # Setup and run GUI
        if self.setup_gui():
            self.run_gui()

        logger.info("Main loop exited. Shutting down.")
        return 0
    
    def update_vosk_max_alternatives(self, value):
        """Update Vosk max alternatives parameter in the active engine"""
        if (self.speech_manager and 
            hasattr(self.speech_manager, 'adapter') and 
            hasattr(self.speech_manager.adapter, 'update_max_alternatives')):
            self.speech_manager.adapter.update_max_alternatives(value)
    
    def update_vosk_beam(self, value):
        """Update Vosk beam parameter in the active engine"""
        if (self.speech_manager and 
            hasattr(self.speech_manager, 'adapter') and 
            hasattr(self.speech_manager.adapter, 'update_beam')):
            self.speech_manager.adapter.update_beam(value)
    
    def update_vosk_lattice_beam(self, value):
        """Update Vosk lattice beam parameter in the active engine"""
        if (self.speech_manager and 
            hasattr(self.speech_manager, 'adapter') and 
            hasattr(self.speech_manager.adapter, 'update_lattice_beam')):
            self.speech_manager.adapter.update_lattice_beam(value)
    
    def update_vosk_confidence_threshold(self, value):
        """Update Vosk confidence threshold in the active engine"""
        if (self.speech_manager and 
            hasattr(self.speech_manager, 'adapter') and 
            hasattr(self.speech_manager.adapter, 'update_confidence_threshold')):
            self.speech_manager.adapter.update_confidence_threshold(value)

def main():
    """Application entry point"""
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

    # Create and run application
    app = TalkieApplication(args)
    return app.run()

if __name__ == "__main__":
    sys.exit(main())