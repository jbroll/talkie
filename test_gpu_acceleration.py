#!/home/john/src/talkie/bin/python3

import os
import time
import logging
import sherpa_onnx
import onnxruntime as ort

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def test_onnx_runtime_direct():
    """Test ONNX Runtime provider selection directly"""
    print("=== Direct ONNX Runtime Test ===")
    print(f"Available providers: {ort.get_available_providers()}")
    
    # Test with OpenVINO provider explicitly
    try:
        providers = ['OpenVINOExecutionProvider', 'CPUExecutionProvider']
        provider_options = [{'device_type': 'GPU_FP32'}, {}]
        
        # Create a simple session to test provider
        session = ort.InferenceSession("models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26/encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx", 
                                     providers=providers,
                                     provider_options=provider_options)
        
        actual_providers = session.get_providers()
        print(f"Session providers: {actual_providers}")
        
        if 'OpenVINOExecutionProvider' in actual_providers[0]:
            print("✓ OpenVINO provider is active")
            return True
        else:
            print("✗ OpenVINO provider not active")
            return False
            
    except Exception as e:
        print(f"✗ Error testing ONNX Runtime: {e}")
        return False

def test_sherpa_different_configs():
    """Test Sherpa-ONNX with different configurations"""
    model_path = "models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26"
    
    configs = [
        {
            'name': 'CPU provider, no OpenVINO env',
            'env': {},
            'provider': 'cpu',
            'num_threads': 2
        },
        {
            'name': 'CPU provider, with OpenVINO env',
            'env': {
                'ORT_PROVIDERS': 'OpenVINOExecutionProvider,CPUExecutionProvider',
                'OV_DEVICE': 'GPU'
            },
            'provider': 'cpu',
            'num_threads': 1
        },
        {
            'name': 'CUDA provider (should fallback)',
            'env': {
                'ORT_PROVIDERS': 'OpenVINOExecutionProvider,CPUExecutionProvider',
                'OV_DEVICE': 'GPU'
            },
            'provider': 'cuda',
            'num_threads': 1
        }
    ]
    
    results = []
    
    for config in configs:
        print(f"\n=== Testing: {config['name']} ===")
        
        # Set environment variables
        original_env = {}
        for key, value in config['env'].items():
            original_env[key] = os.environ.get(key)
            os.environ[key] = value
        
        try:
            start_time = time.time()
            
            # Create recognizer
            recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
                tokens=f"{model_path}/tokens.txt",
                encoder=f"{model_path}/encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
                decoder=f"{model_path}/decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
                joiner=f"{model_path}/joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
                num_threads=config['num_threads'],
                sample_rate=16000,
                provider=config['provider']
            )
            
            init_time = time.time() - start_time
            print(f"✓ Initialization time: {init_time:.3f}s")
            
            # Create stream and test a small amount of processing
            stream = recognizer.create_stream()
            
            # Test with small audio chunk
            import numpy as np
            test_audio = np.zeros(1600, dtype=np.float32)  # 0.1s of silence
            
            start_time = time.time()
            for _ in range(10):  # Process 10 chunks
                stream.accept_waveform(16000, test_audio)
                if recognizer.is_ready(stream):
                    recognizer.decode_stream(stream)
            process_time = time.time() - start_time
            
            print(f"✓ Processing time (10 chunks): {process_time:.3f}s")
            
            results.append({
                'config': config['name'],
                'init_time': init_time,
                'process_time': process_time,
                'success': True
            })
            
        except Exception as e:
            print(f"✗ Error: {e}")
            results.append({
                'config': config['name'],
                'init_time': float('inf'),
                'process_time': float('inf'),
                'success': False,
                'error': str(e)
            })
        
        # Restore environment variables
        for key in config['env'].keys():
            if original_env[key] is not None:
                os.environ[key] = original_env[key]
            else:
                os.environ.pop(key, None)
    
    return results

def main():
    print("Testing GPU Acceleration in Sherpa-ONNX")
    print("=" * 50)
    
    # Test 1: Direct ONNX Runtime
    onnx_works = test_onnx_runtime_direct()
    
    # Test 2: Sherpa-ONNX configurations
    results = test_sherpa_different_configs()
    
    # Summary
    print("\n" + "=" * 50)
    print("SUMMARY")
    print("=" * 50)
    
    print(f"ONNX Runtime OpenVINO: {'✓ Working' if onnx_works else '✗ Not working'}")
    
    print("\nSherpa-ONNX Results:")
    for result in results:
        status = "✓" if result['success'] else "✗"
        init_time = f"{result['init_time']:.3f}s" if result['success'] else "FAILED"
        process_time = f"{result['process_time']:.3f}s" if result['success'] else "FAILED"
        print(f"{status} {result['config']:30} | Init: {init_time:>8} | Process: {process_time:>8}")
    
    # Recommendations
    print("\nRECOMMENDATIONS:")
    
    if onnx_works:
        print("1. OpenVINO execution provider is available")
        
        successful_results = [r for r in results if r['success']]
        if successful_results:
            best_config = min(successful_results, key=lambda x: x['process_time'])
            print(f"2. Best performing config: {best_config['config']}")
            print(f"   - Initialization: {best_config['init_time']:.3f}s")
            print(f"   - Processing: {best_config['process_time']:.3f}s")
        else:
            print("2. No Sherpa-ONNX configurations worked successfully")
            
    else:
        print("1. OpenVINO execution provider is not working properly")
        print("2. Check OpenVINO installation and GPU drivers")

if __name__ == "__main__":
    main()