#!/home/john/src/talkie/bin/python3

import os
import time
import sherpa_onnx
import onnxruntime as ort

def test_modern_openvino_config():
    """Test with modern OpenVINO provider configuration"""
    
    model_path = "models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26"
    
    # Modern OpenVINO provider configuration
    providers = ['OpenVINOExecutionProvider', 'CPUExecutionProvider']
    
    # Updated provider options (not using deprecated GPU_FP32)
    provider_options = [
        {
            'device_type': 'GPU',  # Modern format, not GPU_FP32
            'precision': 'FP16',   # Separate precision setting
            'cache_dir': '/tmp/ov_cache'  # Cache directory
        },
        {}  # CPUExecutionProvider options (empty)
    ]
    
    print("Testing modern OpenVINO configuration...")
    print(f"Providers: {providers}")
    print(f"Options: {provider_options}")
    
    try:
        start_time = time.time()
        
        # Test with direct ONNX Runtime session first
        print("\n1. Testing direct ONNX Runtime session...")
        session = ort.InferenceSession(
            f"{model_path}/encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
            providers=providers,
            provider_options=provider_options
        )
        print(f"✓ Direct ONNX Runtime session created: {session.get_providers()}")
        
        # Now test Sherpa-ONNX
        print("\n2. Testing Sherpa-ONNX with GPU provider...")
        recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
            tokens=f"{model_path}/tokens.txt",
            encoder=f"{model_path}/encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
            decoder=f"{model_path}/decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
            joiner=f"{model_path}/joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
            num_threads=1,
            sample_rate=16000,
            provider="cuda"  # Try CUDA provider which should fallback to available GPU
        )
        
        init_time = time.time() - start_time
        print(f"✓ Sherpa-ONNX GPU initialization: {init_time:.3f}s")
        
        # Quick performance test
        stream = recognizer.create_stream()
        import numpy as np
        test_audio = np.random.rand(1600).astype(np.float32) * 0.001  # Small random audio
        
        start_time = time.time()
        for i in range(100):  # Process more chunks for better timing
            stream.accept_waveform(16000, test_audio)
            if recognizer.is_ready(stream):
                recognizer.decode_stream(stream)
        
        process_time = time.time() - start_time
        print(f"✓ Processing time (100 chunks): {process_time:.3f}s")
        print(f"✓ Per-chunk time: {process_time/100*1000:.2f}ms")
        
        return True
        
    except Exception as e:
        print(f"✗ Error: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_cpu_fallback():
    """Test CPU-only for comparison"""
    
    model_path = "models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26"
    
    print("\n3. Testing CPU-only fallback...")
    
    try:
        start_time = time.time()
        
        recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
            tokens=f"{model_path}/tokens.txt",
            encoder=f"{model_path}/encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
            decoder=f"{model_path}/decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
            joiner=f"{model_path}/joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
            num_threads=2,
            sample_rate=16000,
            provider="cpu"
        )
        
        init_time = time.time() - start_time
        print(f"✓ CPU initialization: {init_time:.3f}s")
        
        # Same performance test
        stream = recognizer.create_stream()
        import numpy as np
        test_audio = np.random.rand(1600).astype(np.float32) * 0.001
        
        start_time = time.time()
        for i in range(100):
            stream.accept_waveform(16000, test_audio)
            if recognizer.is_ready(stream):
                recognizer.decode_stream(stream)
        
        process_time = time.time() - start_time
        print(f"✓ CPU processing time (100 chunks): {process_time:.3f}s")
        print(f"✓ CPU per-chunk time: {process_time/100*1000:.2f}ms")
        
        return True
        
    except Exception as e:
        print(f"✗ CPU Error: {e}")
        return False

def main():
    print("Direct GPU Acceleration Test")
    print("=" * 40)
    
    # Set up environment
    os.environ['LD_LIBRARY_PATH'] = '/home/john/src/talkie/lib/python3.12/site-packages/onnxruntime/capi:' + os.environ.get('LD_LIBRARY_PATH', '')
    
    # Test modern configuration
    gpu_success = test_modern_openvino_config()
    
    # Test CPU fallback for comparison
    cpu_success = test_cpu_fallback()
    
    print("\n" + "=" * 40)
    print("RESULTS SUMMARY")
    print("=" * 40)
    print(f"GPU configuration: {'✓ SUCCESS' if gpu_success else '✗ FAILED'}")
    print(f"CPU configuration: {'✓ SUCCESS' if cpu_success else '✗ FAILED'}")

if __name__ == "__main__":
    main()