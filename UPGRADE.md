# Talkie Migration Plan: Vosk to OpenVINO Whisper NPU

## Overview

This document provides a detailed migration plan to upgrade the Talkie speech-to-text application from Vosk to OpenVINO Whisper with Intel NPU acceleration.

**Current State**: Vosk-based STT using KaldiRecognizer
**Target State**: OpenVINO Whisper with Intel NPU acceleration
**Migration Strategy**: Phased approach with fallback support

## Prerequisites

### Hardware Requirements
- Intel Core Ultra processor with NPU (Meteor Lake or Arrow Lake)
- Ubuntu 20.04+ or 22.04+ LTS
- Minimum 8GB RAM
- 2GB free disk space for models

### Software Requirements
- Python 3.8+
- Intel NPU drivers (installed via kernel modules)
- OpenVINO 2025.0+ runtime
- Current Talkie dependencies

## Phase 1: Environment Setup

### 1.1 Install OpenVINO Runtime

```bash
# Download OpenVINO 2025.1
wget https://storage.openvinotoolkit.org/repositories/openvino/packages/2025.1/linux/l_openvino_toolkit_ubuntu22_2025.1.0.16993.20241121_x86_64.tgz

# Extract and install
tar -xzf l_openvino_toolkit_ubuntu22_2025.1.0.16993.20241121_x86_64.tgz
cd l_openvino_toolkit_ubuntu22_2025.1.0.16993.20241121_x86_64
sudo ./install_dependencies/install_openvino_dependencies.sh
```

### 1.2 Install Python Dependencies

Update `requirements.txt`:
```text
vosk
sounddevice
numpy
pyinput
word2number
openvino>=2025.1.0
openvino-genai>=2025.1.0
optimum[openvino]>=1.15.0
transformers>=4.35.0
torch>=2.0.0
librosa>=0.10.0
soundfile>=0.12.0
```

Install dependencies:
```bash
pip install -r requirements.txt
```

### 1.3 Verify NPU Availability

Create verification script `verify_npu.py`:
```python
import openvino as ov

def check_npu():
    try:
        core = ov.Core()
        devices = core.available_devices
        npu_devices = [d for d in devices if "NPU" in d]
        
        if npu_devices:
            print(f"NPU devices found: {npu_devices}")
            return True
        else:
            print("No NPU devices found")
            return False
    except Exception as e:
        print(f"Error checking NPU: {e}")
        return False

if __name__ == "__main__":
    check_npu()
```

## Phase 2: OpenVINO Whisper Integration

### 2.1 Create OpenVINO Whisper Adapter

Create `openvino_whisper_adapter.py`:
```python
import openvino_genai as ov_genai
import numpy as np
import logging
from typing import Optional, Dict, Any
import threading
import queue
import time

logger = logging.getLogger(__name__)

class OpenVINOWhisperAdapter:
    def __init__(self, model_name: str = "openai/whisper-base", 
                 device: str = "NPU", samplerate: int = 16000):
        self.model_name = model_name
        self.device = device
        self.samplerate = samplerate
        self.pipeline = None
        self.is_initialized = False
        self.audio_buffer = []
        self.buffer_duration = 3.0  # seconds
        self.processing_lock = threading.Lock()
        
    def initialize(self) -> bool:
        """Initialize OpenVINO Whisper pipeline"""
        try:
            logger.info(f"Initializing OpenVINO Whisper: {self.model_name} on {self.device}")
            
            # Convert model if needed
            model_path = self._prepare_model()
            
            # Create pipeline
            self.pipeline = ov_genai.WhisperPipeline(
                str(model_path), 
                device=self.device
            )
            
            self.is_initialized = True
            logger.info("OpenVINO Whisper initialized successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize OpenVINO Whisper: {e}")
            return False
    
    def _prepare_model(self) -> str:
        """Convert model to OpenVINO format if needed"""
        from pathlib import Path
        import subprocess
        import tempfile
        
        model_dir = Path(tempfile.gettempdir()) / f"whisper_ov_{self.model_name.replace('/', '_')}"
        
        if not model_dir.exists() or not (model_dir / "openvino_model.xml").exists():
            logger.info(f"Converting {self.model_name} to OpenVINO format")
            
            cmd = [
                "optimum-cli", "export", "openvino",
                "--model", self.model_name,
                "--task", "automatic-speech-recognition-with-past",
                str(model_dir)
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                raise RuntimeError(f"Model conversion failed: {result.stderr}")
                
            logger.info(f"Model converted to: {model_dir}")
        
        return model_dir
    
    def process_audio_chunk(self, audio_data: bytes) -> Optional[Dict[str, Any]]:
        """Process audio chunk and return transcription result"""
        if not self.is_initialized:
            return None
            
        with self.processing_lock:
            # Convert bytes to float32 array
            audio_np = np.frombuffer(audio_data, dtype=np.int16).astype(np.float32) / 32768.0
            self.audio_buffer.extend(audio_np)
            
            # Process when buffer reaches target duration
            target_samples = int(self.buffer_duration * self.samplerate)
            
            if len(self.audio_buffer) >= target_samples:
                audio_segment = np.array(self.audio_buffer[:target_samples])
                # Keep 50% overlap for better continuity
                self.audio_buffer = self.audio_buffer[target_samples//2:]
                
                try:
                    # Generate transcription
                    result = self.pipeline.generate(audio_segment)
                    
                    if hasattr(result, 'texts') and result.texts:
                        text = result.texts[0].strip()
                        if text:
                            return {
                                'text': text,
                                'is_final': True,
                                'confidence': 0.9  # OpenVINO doesn't provide confidence
                            }
                except Exception as e:
                    logger.error(f"Transcription error: {e}")
        
        return None
    
    def reset(self):
        """Reset audio buffer"""
        with self.processing_lock:
            self.audio_buffer.clear()
    
    def cleanup(self):
        """Clean up resources"""
        if self.pipeline:
            del self.pipeline
        self.pipeline = None
        self.audio_buffer.clear()
        self.is_initialized = False
```

### 2.2 Create Adapter Manager

Create `speech_adapter_manager.py`:
```python
from enum import Enum
from typing import Optional, Callable, Dict, Any
import logging
import queue
import threading
import time

logger = logging.getLogger(__name__)

class EngineType(Enum):
    VOSK = "vosk"
    OPENVINO_WHISPER = "openvino_whisper"

class SpeechResult:
    def __init__(self, text: str, is_final: bool, confidence: float = 0.0):
        self.text = text
        self.is_final = is_final
        self.confidence = confidence

class SpeechAdapterManager:
    def __init__(self, result_callback: Callable[[SpeechResult], None]):
        self.result_callback = result_callback
        self.current_adapter = None
        self.engine_type = None
        self.audio_queue = queue.Queue()
        self.processing_thread = None
        self.running = False
        
    def initialize_engine(self, engine_type: EngineType, **kwargs) -> bool:
        """Initialize speech engine"""
        self.engine_type = engine_type
        
        if engine_type == EngineType.VOSK:
            return self._initialize_vosk(**kwargs)
        elif engine_type == EngineType.OPENVINO_WHISPER:
            return self._initialize_openvino_whisper(**kwargs)
        
        return False
    
    def _initialize_vosk(self, model_path: str, samplerate: int) -> bool:
        """Initialize Vosk adapter (fallback)"""
        try:
            import vosk
            import json
            
            class VoskAdapter:
                def __init__(self, model_path, samplerate):
                    vosk.SetLogLevel(-1)
                    self.model = vosk.Model(model_path)
                    self.recognizer = vosk.KaldiRecognizer(self.model, samplerate)
                    self.recognizer.SetWords(True)
                    
                def process_audio_chunk(self, audio_data):
                    if self.recognizer.AcceptWaveform(audio_data):
                        result = json.loads(self.recognizer.Result())
                        if result.get('text'):
                            return {
                                'text': result['text'],
                                'is_final': True,
                                'confidence': result.get('confidence', 0.0)
                            }
                    else:
                        partial = json.loads(self.recognizer.PartialResult())
                        if partial.get('partial'):
                            return {
                                'text': partial['partial'],
                                'is_final': False,
                                'confidence': 0.0
                            }
                    return None
                
                def reset(self):
                    self.recognizer = vosk.KaldiRecognizer(self.model, samplerate)
                    self.recognizer.SetWords(True)
                
                def cleanup(self):
                    self.model = None
                    self.recognizer = None
            
            self.current_adapter = VoskAdapter(model_path, samplerate)
            logger.info("Vosk adapter initialized")
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize Vosk: {e}")
            return False
    
    def _initialize_openvino_whisper(self, model_name: str = "openai/whisper-base", 
                                   device: str = "NPU", samplerate: int = 16000) -> bool:
        """Initialize OpenVINO Whisper adapter"""
        try:
            from openvino_whisper_adapter import OpenVINOWhisperAdapter
            
            self.current_adapter = OpenVINOWhisperAdapter(model_name, device, samplerate)
            success = self.current_adapter.initialize()
            
            if success:
                logger.info("OpenVINO Whisper adapter initialized")
                return True
            else:
                logger.error("OpenVINO Whisper initialization failed")
                return False
                
        except Exception as e:
            logger.error(f"Failed to initialize OpenVINO Whisper: {e}")
            return False
    
    def start_processing(self):
        """Start audio processing thread"""
        if not self.current_adapter:
            raise RuntimeError("No adapter initialized")
            
        self.running = True
        self.processing_thread = threading.Thread(target=self._processing_loop)
        self.processing_thread.start()
        logger.info("Speech processing started")
    
    def stop_processing(self):
        """Stop audio processing"""
        self.running = False
        if self.processing_thread:
            self.processing_thread.join()
        logger.info("Speech processing stopped")
    
    def add_audio(self, audio_data: bytes):
        """Add audio data to processing queue"""
        if self.running:
            try:
                self.audio_queue.put_nowait(audio_data)
            except queue.Full:
                logger.warning("Audio queue full, dropping frame")
    
    def _processing_loop(self):
        """Main audio processing loop"""
        while self.running:
            try:
                # Get audio data with timeout
                audio_data = self.audio_queue.get(timeout=0.1)
                
                # Process with current adapter
                result_dict = self.current_adapter.process_audio_chunk(audio_data)
                
                if result_dict:
                    result = SpeechResult(
                        text=result_dict['text'],
                        is_final=result_dict['is_final'],
                        confidence=result_dict['confidence']
                    )
                    
                    # Send to callback
                    if self.result_callback:
                        self.result_callback(result)
                        
            except queue.Empty:
                continue
            except Exception as e:
                logger.error(f"Processing error: {e}")
    
    def reset(self):
        """Reset current adapter"""
        if self.current_adapter:
            self.current_adapter.reset()
    
    def cleanup(self):
        """Clean up resources"""
        self.stop_processing()
        if self.current_adapter:
            self.current_adapter.cleanup()
        self.current_adapter = None
```

## Phase 3: Modify Talkie Core

### 3.1 Update Imports and Constants

Add to top of `talkie.py`:
```python
# Add these imports
from speech_adapter_manager import SpeechAdapterManager, EngineType, SpeechResult
from openvino_whisper_adapter import OpenVINOWhisperAdapter

# Add new constants
OPENVINO_MODEL_NAME = "openai/whisper-base"  # Can be changed to other models
NPU_DEVICE = "NPU"
FALLBACK_ENGINE = EngineType.VOSK
```

### 3.2 Replace Global Variables

Replace Vosk-specific globals with:
```python
# Replace transcription globals
speech_manager = None
current_engine = None
```

### 3.3 Create Engine Detection Function

Add before `main()` function:
```python
def detect_best_engine():
    """Detect best available speech engine"""
    try:
        # Check for NPU first
        import openvino as ov
        core = ov.Core()
        devices = core.available_devices
        
        if any("NPU" in device for device in devices):
            logger.info("Intel NPU detected - using OpenVINO Whisper")
            return EngineType.OPENVINO_WHISPER, {
                'model_name': OPENVINO_MODEL_NAME,
                'device': NPU_DEVICE,
                'samplerate': 16000
            }
    except Exception as e:
        logger.warning(f"NPU detection failed: {e}")
    
    # Fallback to Vosk
    logger.info("Using Vosk as fallback engine")
    return EngineType.VOSK, {
        'model_path': DEFAULT_MODEL_PATH,
        'samplerate': 16000
    }
```

### 3.4 Replace Transcribe Function

Replace the existing `transcribe()` function:
```python
def transcribe(device_id, samplerate, block_duration, queue_size, model_config):
    global transcribing, q, speech_start_time, app, running, processing_state
    global number_buffer, number_mode_start_time, speech_manager
    
    print("Transcribe function started")
    logger.info("Transcribe function started")
    
    # Initialize speech manager
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
    
    # Create speech manager
    speech_manager = SpeechAdapterManager(handle_speech_result)
    
    # Detect and initialize best engine
    engine_type, engine_config = detect_best_engine()
    
    if not speech_manager.initialize_engine(engine_type, **engine_config):
        logger.error("Failed to initialize speech engine")
        return
    
    # Start speech processing
    speech_manager.start_processing()
    
    # Initialize audio queue and processing
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
                        # Handle number timeout (existing logic)
                        if processing_state == ProcessingState.NUMBER and number_mode_start_time:
                            if time.time() - number_mode_start_time > NUMBER_TIMEOUT:
                                logger.debug("Number timeout in main loop")
                                process_text("", is_final=True)
                        
                        # Get audio data and send to speech manager
                        data = q.get(timeout=0.1)
                        speech_manager.add_audio(data)
                        
                    except queue.Empty:
                        # Handle timeout logic (existing code)
                        if processing_state == ProcessingState.NUMBER and number_mode_start_time:
                            if time.time() - number_mode_start_time > NUMBER_TIMEOUT:
                                logger.debug("Number timeout on empty queue")
                                process_text("", is_final=True)
                else:
                    # Reset logic when transcription is off (existing code)
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
    
    logger.info("Transcribe function ending")
    print("Transcribe function ending")
```

### 3.5 Update Main Function

Modify `main()` function:
```python
def main():
    global running, app
    
    parser = argparse.ArgumentParser(description='Talkie - Speech to Text')
    parser.add_argument('--model', help='Path to Vosk model (fallback only)')
    parser.add_argument('--whisper-model', default='openai/whisper-base', 
                       help='OpenVINO Whisper model name')
    parser.add_argument('--engine', choices=['auto', 'vosk', 'openvino'], 
                       default='auto', help='Force specific engine')
    parser.add_argument('--no-gui', action='store_true', help='Run without GUI')
    
    args = parser.parse_args()
    
    try:
        # Setup virtual input device
        uinput_setup()
        
        # Prepare model configuration based on args
        if args.engine == 'vosk':
            engine_type = EngineType.VOSK
            model_config = {
                'model_path': args.model or DEFAULT_MODEL_PATH,
                'samplerate': 16000
            }
        elif args.engine == 'openvino':
            engine_type = EngineType.OPENVINO_WHISPER
            model_config = {
                'model_name': args.whisper_model,
                'device': NPU_DEVICE,
                'samplerate': 16000
            }
        else:  # auto
            engine_type, model_config = detect_best_engine()
            if args.whisper_model != 'openai/whisper-base':
                model_config['model_name'] = args.whisper_model
        
        if not args.no_gui:
            # Create and start GUI
            app = TalkieApp()
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
                transcribe(device_id, samplerate, BLOCK_DURATION, QUEUE_SIZE, model_config)
                
    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        cleanup()
```

## Phase 4: Testing and Validation

### 4.1 Create Test Scripts

Create `test_engines.py`:
```python
#!/usr/bin/env python3
import logging
import time
import numpy as np
from speech_adapter_manager import SpeechAdapterManager, EngineType, SpeechResult

logging.basicConfig(level=logging.INFO)

def test_engine(engine_type: EngineType, **kwargs):
    """Test specific speech engine"""
    print(f"\n=== Testing {engine_type.value} ===")
    
    results = []
    
    def collect_result(result: SpeechResult):
        results.append(result)
        print(f"Result: {result.text} (final: {result.is_final})")
    
    manager = SpeechAdapterManager(collect_result)
    
    # Initialize engine
    if not manager.initialize_engine(engine_type, **kwargs):
        print(f"Failed to initialize {engine_type.value}")
        return False
    
    # Start processing
    manager.start_processing()
    
    # Generate test audio (1 second of sine wave)
    samplerate = kwargs.get('samplerate', 16000)
    duration = 1.0
    frequency = 440  # A note
    
    t = np.linspace(0, duration, int(samplerate * duration), False)
    audio_signal = np.sin(2 * np.pi * frequency * t)
    audio_bytes = (audio_signal * 32767).astype(np.int16).tobytes()
    
    # Send test audio
    start_time = time.time()
    manager.add_audio(audio_bytes)
    
    # Wait for results
    time.sleep(3)
    processing_time = time.time() - start_time
    
    manager.cleanup()
    
    print(f"Processing time: {processing_time:.2f}s")
    print(f"Results received: {len(results)}")
    
    return len(results) > 0

if __name__ == "__main__":
    # Test OpenVINO Whisper
    success_ov = test_engine(
        EngineType.OPENVINO_WHISPER,
        model_name="openai/whisper-base",
        device="NPU",
        samplerate=16000
    )
    
    # Test Vosk fallback
    success_vosk = test_engine(
        EngineType.VOSK,
        model_path="/path/to/vosk/model",  # Update path
        samplerate=16000
    )
    
    print(f"\n=== Test Summary ===")
    print(f"OpenVINO Whisper: {'PASS' if success_ov else 'FAIL'}")
    print(f"Vosk: {'PASS' if success_vosk else 'FAIL'}")
```

### 4.2 Performance Benchmarking

Create `benchmark_performance.py`:
```python
#!/usr/bin/env python3
import time
import numpy as np
import logging
from speech_adapter_manager import SpeechAdapterManager, EngineType, SpeechResult

logging.basicConfig(level=logging.WARNING)

def benchmark_engine(engine_type: EngineType, test_duration: float = 10.0, **kwargs):
    """Benchmark speech engine performance"""
    
    results = []
    
    def collect_result(result: SpeechResult):
        if result.is_final:
            results.append({
                'text': result.text,
                'timestamp': time.time(),
                'confidence': result.confidence
            })
    
    manager = SpeechAdapterManager(collect_result)
    
    if not manager.initialize_engine(engine_type, **kwargs):
        return None
    
    manager.start_processing()
    
    # Generate continuous test audio
    samplerate = kwargs.get('samplerate', 16000)
    chunk_duration = 0.1  # 100ms chunks
    chunk_samples = int(samplerate * chunk_duration)
    
    start_time = time.time()
    audio_sent = 0
    
    while time.time() - start_time < test_duration:
        # Generate chunk of audio
        t = np.linspace(0, chunk_duration, chunk_samples, False)
        frequency = 440 + (time.time() - start_time) * 10  # Varying frequency
        audio_signal = np.sin(2 * np.pi * frequency * t) * 0.5
        audio_bytes = (audio_signal * 32767).astype(np.int16).tobytes()
        
        manager.add_audio(audio_bytes)
        audio_sent += chunk_duration
        
        time.sleep(chunk_duration)
    
    # Wait for final results
    time.sleep(2)
    
    total_time = time.time() - start_time
    manager.cleanup()
    
    return {
        'engine': engine_type.value,
        'total_time': total_time,
        'audio_duration': audio_sent,
        'results_count': len(results),
        'real_time_factor': audio_sent / total_time if total_time > 0 else 0,
        'avg_confidence': sum(r['confidence'] for r in results) / len(results) if results else 0
    }

if __name__ == "__main__":
    print("=== Performance Benchmark ===")
    
    # Benchmark OpenVINO Whisper
    print("Benchmarking OpenVINO Whisper...")
    ov_results = benchmark_engine(
        EngineType.OPENVINO_WHISPER,
        model_name="openai/whisper-base",
        device="NPU",
        samplerate=16000,
        test_duration=5.0
    )
    
    if ov_results:
        print(f"OpenVINO Results:")
        print(f"  Real-time factor: {ov_results['real_time_factor']:.2f}x")
        print(f"  Results generated: {ov_results['results_count']}")
        print(f"  Average confidence: {ov_results['avg_confidence']:.2f}")
    
    # Benchmark Vosk
    print("\nBenchmarking Vosk...")
    vosk_results = benchmark_engine(
        EngineType.VOSK,
        model_path="/path/to/vosk/model",  # Update path
        samplerate=16000,
        test_duration=5.0
    )
    
    if vosk_results:
        print(f"Vosk Results:")
        print(f"  Real-time factor: {vosk_results['real_time_factor']:.2f}x")
        print(f"  Results generated: {vosk_results['results_count']}")
        print(f"  Average confidence: {vosk_results['avg_confidence']:.2f}")
    
    # Comparison
    if ov_results and vosk_results:
        speedup = ov_results['real_time_factor'] / vosk_results['real_time_factor']
        print(f"\nOpenVINO vs Vosk speedup: {speedup:.2f}x")
```

## Phase 5: Deployment

### 5.1 Update File Structure

```
talkie/
├── talkie.py                    # Updated main file
├── speech_adapter_manager.py    # New adapter manager
├── openvino_whisper_adapter.py  # New OpenVINO adapter  
├── requirements.txt             # Updated dependencies
├── test_engines.py              # Engine testing
├── benchmark_performance.py     # Performance testing
├── verify_npu.py               # NPU verification
└── models/                     # Model storage
    ├── vosk/                   # Vosk models (fallback)
    └── whisper_ov/             # Converted OpenVINO models
```

### 5.2 Update Launch Commands

Create `launch_talkie.sh`:
```bash
#!/bin/bash

# Set OpenVINO environment
source /opt/intel/openvino_2025/setupvars.sh

# Verify NPU availability
python3 verify_npu.py

if [ $? -eq 0 ]; then
    echo "NPU detected - launching with OpenVINO Whisper"
    python3 talkie.py --engine auto --whisper-model openai/whisper-base
else
    echo "No NPU detected - launching with Vosk fallback"
    python3 talkie.py --engine vosk --model ./models/vosk-model-en-us-0.22-lgraph
fi
```

### 5.3 Deployment Checklist

- [ ] Install OpenVINO 2025.1+
- [ ] Verify NPU drivers loaded (`lsmod | grep intel_vpu`)
- [ ] Install Python dependencies
- [ ] Run NPU verification script
- [ ] Test engines with test script
- [ ] Run performance benchmark
- [ ] Update Talkie code files
- [ ] Test complete application
- [ ] Create launch script
- [ ] Document configuration options

## Phase 6: Configuration Options

### 6.1 Model Selection

Available Whisper models (in order of size/accuracy):
- `openai/whisper-tiny` - Fastest, lowest accuracy
- `openai/whisper-base` - Balanced (recommended)  
- `openai/whisper-small` - Higher accuracy, slower
- `openai/whisper-medium` - High accuracy, much slower
- `distil-whisper/distil-large-v2` - Optimized large model

### 6.2 Device Priority

Automatic device selection order:
1. Intel NPU (if available)
2. Intel GPU (if available)  
3. CPU with OpenVINO optimization
4. Vosk fallback (if OpenVINO fails)

### 6.3 Runtime Parameters

Environment variables for tuning:
```bash
export OPENVINO_LOG_LEVEL=1              # OpenVINO logging
export OV_CACHE_DIR=./models/cache       # Model cache location  
export WHISPER_BUFFER_DURATION=3.0       # Audio buffer duration (seconds)
export WHISPER_OVERLAP_RATIO=0.5         # Buffer overlap ratio
```

## Phase 7: Troubleshooting

### 7.1 Common Issues

**NPU Not Detected**:
```bash
# Check NPU driver
lsmod | grep intel_vpu
sudo modprobe intel_vpu

# Check OpenVINO devices
python3 -c "import openvino as ov; print(ov.Core().available_devices)"

# Verify Intel NPU driver version
cat /sys/module/intel_vpu/version
```

**Model Conversion Fails**:
```bash
# Manual model conversion
optimum-cli export openvino \
  --model openai/whisper-base \
  --task automatic-speech-recognition-with-past \
  ./models/whisper-base-ov

# Check disk space
df -h ./models/
```

**Audio Processing Issues**:
```bash
# Check audio device permissions
groups $USER | grep audio
sudo usermod -a -G audio $USER

# Test audio capture
arecord -d 5 -f cd test.wav
```

### 7.2 Performance Optimization

**Memory Usage**:
```python
# Add to adapter initialization
import gc
gc.collect()  # Force garbage collection

# Monitor memory usage
import psutil
process = psutil.Process()
memory_mb = process.memory_info().rss / 1024 / 1024
logger.info(f"Memory usage: {memory_mb:.1f} MB")
```

**Latency Reduction**:
```python
# Reduce buffer duration for lower latency
self.buffer_duration = 1.5  # Reduce from 3.0 seconds

# Increase processing thread priority
import os
os.nice(-5)  # Higher priority (requires privileges)
```

### 7.3 Debug Logging

Create `debug_config.py`:
```python
import logging
import sys

def setup_debug_logging():
    """Configure detailed logging for debugging"""
    
    # Create formatters
    detailed_formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(filename)s:%(lineno)d - %(message)s'
    )
    
    # File handler for debug logs
    file_handler = logging.FileHandler('talkie_debug.log')
    file_handler.setLevel(logging.DEBUG)
    file_handler.setFormatter(detailed_formatter)
    
    # Console handler for important messages
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.INFO)
    console_handler.setFormatter(logging.Formatter('%(levelname)s: %(message)s'))
    
    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.DEBUG)
    root_logger.addHandler(file_handler)
    root_logger.addHandler(console_handler)
    
    # Configure specific loggers
    logging.getLogger('openvino').setLevel(logging.WARNING)
    logging.getLogger('transformers').setLevel(logging.WARNING)
    logging.getLogger('urllib3').setLevel(logging.WARNING)

if __name__ == "__main__":
    setup_debug_logging()
```

Add to main talkie.py:
```python
# Add at top of main() function
if args.debug:
    from debug_config import setup_debug_logging
    setup_debug_logging()
```

## Phase 8: Rollback Plan

### 8.1 Backup Current Version

```bash
# Create backup before migration
cp talkie.py talkie.py.backup
cp requirements.txt requirements.txt.backup
tar -czf talkie_backup_$(date +%Y%m%d).tar.gz *.py requirements.txt
```

### 8.2 Rollback Procedure

If migration fails, restore original functionality:

```bash
# Restore original files
cp talkie.py.backup talkie.py
cp requirements.txt.backup requirements.txt

# Remove new dependencies
pip uninstall openvino openvino-genai optimum

# Reinstall original requirements
pip install -r requirements.txt
```

### 8.3 Hybrid Mode

Create `talkie_hybrid.py` that supports both engines:
```python
# Add command line option for engine selection
parser.add_argument('--force-vosk', action='store_true', 
                   help='Force use of Vosk engine')

# In main function
if args.force_vosk:
    engine_type = EngineType.VOSK
    model_config = {'model_path': DEFAULT_MODEL_PATH, 'samplerate': 16000}
else:
    engine_type, model_config = detect_best_engine()
```

## Phase 9: Documentation Updates

### 9.1 Update README.md

```markdown
# Talkie - Speech to Text Application

## Hardware Requirements

### Minimum Requirements
- Ubuntu 20.04+ LTS
- 4GB RAM
- 1GB free disk space

### Recommended Requirements  
- Intel Core Ultra processor with NPU
- 8GB RAM
- 2GB free disk space

## Installation

### Basic Installation
```bash
git clone <repository>
cd talkie
pip install -r requirements.txt
```

### Intel NPU Support
```bash
# Install OpenVINO
wget https://storage.openvinotoolkit.org/repositories/openvino/packages/2025.1/linux/l_openvino_toolkit_ubuntu22_2025.1.0.16993.20241121_x86_64.tgz
tar -xzf l_openvino_toolkit_ubuntu22_2025.1.0.16993.20241121_x86_64.tgz
cd l_openvino_toolkit_ubuntu22_2025.1.0.16993.20241121_x86_64
sudo ./install_dependencies/install_openvino_dependencies.sh

# Install Python dependencies
pip install -r requirements.txt

# Verify NPU
python3 verify_npu.py
```

## Usage

### Automatic Engine Selection
```bash
python3 talkie.py
```

### Force Specific Engine
```bash
# Use OpenVINO Whisper
python3 talkie.py --engine openvino --whisper-model openai/whisper-base

# Use Vosk fallback
python3 talkie.py --engine vosk --model /path/to/vosk/model
```

### Available Models
- `openai/whisper-tiny` - Fastest
- `openai/whisper-base` - Balanced (default)
- `openai/whisper-small` - Higher accuracy
- `distil-whisper/distil-large-v2` - Optimized large model

## Performance Testing
```bash
# Test engine functionality
python3 test_engines.py

# Benchmark performance
python3 benchmark_performance.py
```

## Troubleshooting

See Phase 7 of migration documentation for detailed troubleshooting steps.
```

### 9.2 Create User Manual

Create `USER_MANUAL.md`:
```markdown
# Talkie User Manual

## Quick Start

1. **Launch Application**
   ```bash
   ./launch_talkie.sh
   ```

2. **Start Transcription**
   - Press and hold Right Ctrl key
   - Speak clearly into microphone
   - Release Right Ctrl key
   - Text appears in focused window

## Configuration

### Model Selection
Edit `launch_talkie.sh` to change default model:
```bash
python3 talkie.py --whisper-model openai/whisper-small
```

### Audio Device
Select audio device on first launch or use:
```bash
python3 talkie.py --list-devices
```

### Hotkey Configuration
Default hotkey is Right Ctrl. To change, modify `listen_for_hotkey()` function.

## Performance Tips

1. **For Faster Response**: Use `whisper-tiny` model
2. **For Better Accuracy**: Use `whisper-small` or `whisper-base` 
3. **For Multilingual**: Use standard models (not .en variants)
4. **For Low Memory**: Use quantized models with INT8 compute type

## Keyboard Shortcuts

- **Right Ctrl**: Push-to-talk transcription
- **Ctrl+C**: Quit application (terminal mode)
- **Alt+F4**: Close GUI window

## Status Indicators

- **Green**: NPU/GPU acceleration active
- **Yellow**: CPU processing
- **Red**: Engine error or fallback mode
- **Blue**: Processing audio

## Common Issues

### No Text Output
1. Check microphone permissions
2. Verify audio device selection
3. Test with: `arecord -d 5 test.wav`

### Slow Processing  
1. Check available RAM
2. Try smaller model (whisper-tiny)
3. Close other applications

### NPU Not Working
1. Verify Intel Core Ultra processor
2. Check NPU drivers: `lsmod | grep intel_vpu`
3. Run: `python3 verify_npu.py`
```

## Phase 10: Testing Matrix

### 10.1 Hardware Test Matrix

| Hardware Config | Expected Engine | Test Status | Notes |
|----------------|-----------------|-------------|-------|
| Intel Core Ultra + NPU | OpenVINO (NPU) | [ ] | Primary target |
| Intel Core Ultra (no NPU) | OpenVINO (iGPU) | [ ] | Secondary target |  
| Intel CPU + NVIDIA GPU | OpenVINO (CPU) | [ ] | Fallback case |
| AMD CPU + GPU | Vosk | [ ] | Full fallback |
| Generic CPU only | Vosk | [ ] | Minimum spec |

### 10.2 Model Test Matrix

| Model | Size | Speed | Accuracy | Test Status |
|-------|------|-------|----------|-------------|
| whisper-tiny | 39MB | Fastest | Lowest | [ ] |
| whisper-base | 142MB | Fast | Good | [ ] |  
| whisper-small | 461MB | Medium | Better | [ ] |
| distil-large-v2 | 756MB | Fast | High | [ ] |

### 10.3 Functionality Test Cases

```python
# Create test_cases.py
test_cases = [
    {
        'name': 'Basic transcription',
        'input': 'Hello world this is a test',
        'expected_contains': ['hello', 'world', 'test'],
        'test_function': test_basic_transcription
    },
    {
        'name': 'Number processing', 
        'input': 'The price is twenty five dollars',
        'expected_contains': ['price', '25', 'dollars'],
        'test_function': test_number_conversion
    },
    {
        'name': 'Punctuation handling',
        'input': 'This is a sentence period New sentence',
        'expected_contains': ['.', 'sentence'],
        'test_function': test_punctuation
    },
    {
        'name': 'Engine switching',
        'input': 'Test engine switching capability', 
        'expected_behavior': 'successful_switch',
        'test_function': test_engine_switching
    },
    {
        'name': 'Long audio processing',
        'input': '60_second_speech.wav',
        'expected_behavior': 'complete_transcription',
        'test_function': test_long_audio
    }
]
```

## Phase 11: Performance Monitoring

### 11.1 Create Performance Monitor

Create `performance_monitor.py`:
```python
import time
import psutil
import threading
import logging
from typing import Dict, List

logger = logging.getLogger(__name__)

class PerformanceMonitor:
    def __init__(self):
        self.metrics = {
            'processing_times': [],
            'memory_usage': [],
            'cpu_usage': [],
            'transcription_latency': [],
            'engine_switches': 0,
            'errors': 0
        }
        self.monitoring = False
        self.monitor_thread = None
        
    def start_monitoring(self):
        """Start performance monitoring"""
        self.monitoring = True
        self.monitor_thread = threading.Thread(target=self._monitor_loop)
        self.monitor_thread.start()
        logger.info("Performance monitoring started")
        
    def stop_monitoring(self):
        """Stop performance monitoring and generate report"""
        self.monitoring = False
        if self.monitor_thread:
            self.monitor_thread.join()
        self._generate_report()
        
    def _monitor_loop(self):
        """Main monitoring loop"""
        process = psutil.Process()
        
        while self.monitoring:
            try:
                # Collect metrics
                cpu_percent = process.cpu_percent()
                memory_mb = process.memory_info().rss / 1024 / 1024
                
                self.metrics['cpu_usage'].append(cpu_percent)
                self.metrics['memory_usage'].append(memory_mb)
                
                time.sleep(1)
                
            except Exception as e:
                logger.error(f"Monitoring error: {e}")
                self.metrics['errors'] += 1
                
    def record_transcription(self, processing_time: float, latency: float):
        """Record transcription metrics"""
        self.metrics['processing_times'].append(processing_time)
        self.metrics['transcription_latency'].append(latency)
        
    def record_engine_switch(self):
        """Record engine switch event"""
        self.metrics['engine_switches'] += 1
        
    def _generate_report(self):
        """Generate performance report"""
        if not any(self.metrics['processing_times']):
            logger.warning("No performance data collected")
            return
            
        report = {
            'avg_processing_time': sum(self.metrics['processing_times']) / len(self.metrics['processing_times']),
            'avg_memory_usage': sum(self.metrics['memory_usage']) / len(self.metrics['memory_usage']),
            'avg_cpu_usage': sum(self.metrics['cpu_usage']) / len(self.metrics['cpu_usage']),
            'avg_latency': sum(self.metrics['transcription_latency']) / len(self.metrics['transcription_latency']),
            'total_transcriptions': len(self.metrics['processing_times']),
            'engine_switches': self.metrics['engine_switches'],
            'errors': self.metrics['errors']
        }
        
        logger.info("=== Performance Report ===")
        logger.info(f"Average processing time: {report['avg_processing_time']:.3f}s")
        logger.info(f"Average memory usage: {report['avg_memory_usage']:.1f} MB")
        logger.info(f"Average CPU usage: {report['avg_cpu_usage']:.1f}%")
        logger.info(f"Average latency: {report['avg_latency']:.3f}s")
        logger.info(f"Total transcriptions: {report['total_transcriptions']}")
        logger.info(f"Engine switches: {report['engine_switches']}")
        logger.info(f"Errors: {report['errors']}")
        
        return report

# Integration example for talkie.py
performance_monitor = PerformanceMonitor()

def enhanced_handle_speech_result(result: SpeechResult):
    """Enhanced result handler with performance monitoring"""
    end_time = time.time()
    processing_time = end_time - getattr(result, 'start_time', end_time)
    latency = end_time - getattr(result, 'audio_timestamp', end_time)
    
    # Record metrics
    performance_monitor.record_transcription(processing_time, latency)
    
    # Original handling
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
```

### 11.2 Integration with Talkie

Add to main talkie.py:
```python
# Import performance monitor
from performance_monitor import PerformanceMonitor

# Initialize in main()
performance_monitor = PerformanceMonitor()
performance_monitor.start_monitoring()

# Add to cleanup()
def cleanup():
    global virtual_device, performance_monitor
    if performance_monitor:
        performance_monitor.stop_monitoring()
    # ... existing cleanup code
```

## Phase 12: Final Validation

### 12.1 Complete System Test

Create `system_test.py`:
```python
#!/usr/bin/env python3
"""Complete system test for Talkie migration"""

import subprocess
import sys
import os
import time
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class SystemTest:
    def __init__(self):
        self.test_results = {}
        
    def run_all_tests(self):
        """Run complete system test suite"""
        
        tests = [
            ('NPU Detection', self.test_npu_detection),
            ('Dependencies', self.test_dependencies),
            ('Model Conversion', self.test_model_conversion),
            ('Engine Initialization', self.test_engine_init),
            ('Audio Processing', self.test_audio_processing),
            ('Performance Benchmark', self.test_performance),
            ('GUI Launch', self.test_gui_launch),
            ('CLI Launch', self.test_cli_launch)
        ]
        
        logger.info("Starting complete system test...")
        
        for test_name, test_func in tests:
            logger.info(f"Running {test_name}...")
            try:
                result = test_func()
                self.test_results[test_name] = 'PASS' if result else 'FAIL'
                logger.info(f"{test_name}: {'PASS' if result else 'FAIL'}")
            except Exception as e:
                self.test_results[test_name] = f'ERROR: {e}'
                logger.error(f"{test_name}: ERROR: {e}")
        
        self.generate_report()
        
    def test_npu_detection(self) -> bool:
        """Test NPU detection"""
        result = subprocess.run([sys.executable, 'verify_npu.py'], 
                              capture_output=True, text=True)
        return result.returncode == 0
        
    def test_dependencies(self) -> bool:
        """Test all required dependencies"""
        required_packages = [
            'openvino', 'openvino_genai', 'optimum',
            'transformers', 'torch', 'sounddevice', 'numpy'
        ]
        
        for package in required_packages:
            try:
                __import__(package)
            except ImportError:
                logger.error(f"Missing package: {package}")
                return False
        return True
        
    def test_model_conversion(self) -> bool:
        """Test model conversion process"""
        try:
            result = subprocess.run([
                'optimum-cli', 'export', 'openvino',
                '--model', 'openai/whisper-tiny',
                '--task', 'automatic-speech-recognition-with-past',
                '/tmp/test_whisper_conversion'
            ], capture_output=True, text=True, timeout=300)
            
            success = result.returncode == 0
            if success:
                # Cleanup test conversion
                subprocess.run(['rm', '-rf', '/tmp/test_whisper_conversion'])
            return success
        except subprocess.TimeoutExpired:
            logger.error("Model conversion timed out")
            return False
            
    def test_engine_init(self) -> bool:
        """Test engine initialization"""
        result = subprocess.run([sys.executable, 'test_engines.py'], 
                              capture_output=True, text=True)
        return result.returncode == 0
        
    def test_audio_processing(self) -> bool:
        """Test audio processing pipeline"""
        # Create a test audio file
        result = subprocess.run([
            'ffmpeg', '-f', 'lavfi', '-i', 'testsrc2=duration=5:size=320x240:rate=1',
            '-f', 'lavfi', '-i', 'sine=frequency=1000:duration=5',
            '-shortest', '/tmp/test_audio.wav'
        ], capture_output=True)
        
        if result.returncode != 0:
            return False
            
        # Test with talkie
        result = subprocess.run([
            sys.executable, 'talkie.py', '--no-gui', '--test-audio', '/tmp/test_audio.wav'
        ], capture_output=True, text=True, timeout=30)
        
        # Cleanup
        subprocess.run(['rm', '-f', '/tmp/test_audio.wav'])
        
        return result.returncode == 0
        
    def test_performance(self) -> bool:
        """Test performance benchmarking"""
        result = subprocess.run([sys.executable, 'benchmark_performance.py'], 
                              capture_output=True, text=True, timeout=60)
        return result.returncode == 0
        
    def test_gui_launch(self) -> bool:
        """Test GUI launch (non-interactive)"""
        # Set display to virtual if available
        env = os.environ.copy()
        env['DISPLAY'] = ':99'  # Virtual display
        
        process = subprocess.Popen([
            sys.executable, 'talkie.py'
        ], env=env)
        
        time.sleep(3)  # Let it start
        process.terminate()
        process.wait()
        
        return process.returncode == 0 or process.returncode == -15  # SIGTERM
        
    def test_cli_launch(self) -> bool:
        """Test CLI launch"""
        process = subprocess.Popen([
            sys.executable, 'talkie.py', '--no-gui'
        ])
        
        time.sleep(2)  # Let it start
        process.terminate()
        process.wait()
        
        return process.returncode == 0 or process.returncode == -15  # SIGTERM
        
    def generate_report(self):
        """Generate final test report"""
        logger.info("\n" + "="*50)
        logger.info("SYSTEM TEST REPORT")
        logger.info("="*50)
        
        passed = sum(1 for result in self.test_results.values() if result == 'PASS')
        total = len(self.test_results)
        
        for test_name, result in self.test_results.items():
            status = "✓" if result == 'PASS' else "✗"
            logger.info(f"{status} {test_name}: {result}")
            
        logger.info(f"\nSummary: {passed}/{total} tests passed")
        
        if passed == total:
            logger.info("🎉 All tests passed! Migration successful.")
            return True
        else:
            logger.error("❌ Some tests failed. Check logs for details.")
            return False

if __name__ == "__main__":
    test_suite = SystemTest()
    success = test_suite.run_all_tests()
    sys.exit(0 if success else 1)
```

### 12.2 Migration Completion Checklist

- [ ] Phase 1: Environment setup completed
- [ ] Phase 2: OpenVINO integration working  
- [ ] Phase 3: Talkie core modified
- [ ] Phase 4: Tests passing
- [ ] Phase 5: Deployment successful
- [ ] Phase 6: Configuration documented
- [ ] Phase 7: Troubleshooting guide ready
- [ ] Phase 8: Rollback plan tested
- [ ] Phase 9: Documentation updated
- [ ] Phase 10: Test matrix completed
- [ ] Phase 11: Performance monitoring active
- [ ] Phase 12: System test passing

### 12.3 Post-Migration Tasks

1. **Performance Optimization**
   - Monitor real-world usage for 1 week
   - Adjust buffer sizes based on latency requirements  
   - Fine-tune model selection for accuracy vs speed

2. **User Training**
   - Update user documentation
   - Provide migration guide for existing users
   - Document new features and capabilities

3. **Maintenance Plan**
   - Schedule monthly OpenVINO updates
   - Monitor for new Whisper model releases
   - Plan Intel NPU driver update schedule

4. **Future Enhancements**
   - Investigate streaming Whisper implementations
   - Explore multi-language detection
   - Consider speaker diarization features

## Conclusion

This migration plan provides a comprehensive, step-by-step approach to upgrade Talkie from Vosk to OpenVINO Whisper with Intel NPU support. The phased approach ensures minimal downtime and provides fallback options at each stage.

Key benefits of the migration:
- Significant performance improvement with NPU acceleration
- Future-proofing for Intel AI PC ecosystem  
- Maintained backward compatibility with Vosk
- Comprehensive testing and monitoring framework
- Detailed troubleshooting and rollback procedures

The migration preserves all existing Talkie functionality while adding substantial performance improvements and new capabilities.