#!/home/john/src/talkie/bin/python3

import os
import time
import sherpa_onnx
import onnxruntime as ort

def test_fixed_batch_size():
    """Test with fixed batch size to resolve dynamic shape issues"""
    
    model_path = "models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26"
    
    # OpenVINO provider with fixed batch size configuration
    providers = ['OpenVINOExecutionProvider', 'CPUExecutionProvider']
    
    # Force fixed batch size by setting input shapes
    provider_options = [
        {
            'device_type': 'GPU',
            'precision': 'FP16',
            'cache_dir': '/tmp/ov_cache',
            # Try to force batch size = 1 for all dynamic dimensions
            'input_names': 'x,cached_key_0,cached_nonlin_attn_0',  # Key input names
            'input_shapes': '[1,45,80],[128,1,128],[1,1,128,144]'  # Fixed shapes with N=1
        },
        {}
    ]
    
    print("Testing OpenVINO with fixed batch size...")
    print(f"Providers: {providers}")
    print(f"Options: {provider_options}")
    
    try:
        start_time = time.time()
        
        print("\n1. Creating ONNX Runtime session with fixed shapes...")
        session = ort.InferenceSession(
            f"{model_path}/encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
            providers=providers,
            provider_options=provider_options
        )
        
        actual_providers = session.get_providers()
        print(f"✓ Session created with providers: {actual_providers}")
        
        if 'OpenVINOExecutionProvider' == actual_providers[0]:
            print("✓ OpenVINO provider is active!")
        else:
            print("⚠ Fallback to CPU provider")
        
        init_time = time.time() - start_time
        print(f"✓ ONNX Session init time: {init_time:.3f}s")
        
        return True
        
    except Exception as e:
        print(f"✗ Error with fixed shapes: {e}")
        
        # Try simpler approach - just GPU device without input shape fixing
        try:
            print("\n2. Trying simplified GPU configuration...")
            provider_options_simple = [
                {
                    'device_type': 'GPU',
                    'precision': 'FP32'  # Use FP32 instead of FP16
                },
                {}
            ]
            
            session = ort.InferenceSession(
                f"{model_path}/encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
                providers=['CPUExecutionProvider']  # Force CPU first to test
            )
            print("✓ CPU-only session works as fallback")
            
        except Exception as e2:
            print(f"✗ Even CPU fallback failed: {e2}")
        
        return False

def test_sherpa_onnx_different_providers():
    """Test Sherpa-ONNX with different provider configurations"""
    
    model_path = "models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26"
    
    configs = [
        {
            'name': 'Sherpa-ONNX with CUDA provider (should use OpenVINO)',
            'provider': 'cuda',
            'env': {
                'ORT_PROVIDERS': 'OpenVINOExecutionProvider,CPUExecutionProvider',
                'OV_DEVICE': 'GPU'
            }
        },
        {
            'name': 'Sherpa-ONNX with CPU provider + OpenVINO env',
            'provider': 'cpu',
            'env': {
                'ORT_PROVIDERS': 'OpenVINOExecutionProvider,CPUExecutionProvider',
                'OV_DEVICE': 'CPU'  # Try CPU device instead of GPU
            }
        },
        {
            'name': 'Sherpa-ONNX pure CPU (no OpenVINO)',
            'provider': 'cpu',
            'env': {}
        }
    ]
    
    results = []
    
    for config in configs:
        print(f"\n=== {config['name']} ===")
        
        # Set environment
        original_env = {}
        for key, value in config['env'].items():
            original_env[key] = os.environ.get(key)
            os.environ[key] = value
        
        try:
            start_time = time.time()
            
            recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
                tokens=f"{model_path}/tokens.txt",
                encoder=f"{model_path}/encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
                decoder=f"{model_path}/decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
                joiner=f"{model_path}/joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
                num_threads=1,
                sample_rate=16000,
                provider=config['provider']
            )
            
            init_time = time.time() - start_time
            print(f"✓ Initialization: {init_time:.3f}s")
            
            # Quick performance test
            stream = recognizer.create_stream()
            import numpy as np
            test_audio = np.random.rand(1600).astype(np.float32) * 0.001
            
            start_time = time.time()
            for i in range(50):  # Smaller test
                stream.accept_waveform(16000, test_audio)
                if recognizer.is_ready(stream):
                    recognizer.decode_stream(stream)
            
            process_time = time.time() - start_time
            per_chunk_ms = process_time / 50 * 1000
            
            print(f"✓ Processing (50 chunks): {process_time:.3f}s ({per_chunk_ms:.2f}ms/chunk)")
            
            results.append({
                'name': config['name'],
                'init_time': init_time,
                'process_time': process_time,
                'per_chunk_ms': per_chunk_ms,
                'success': True
            })
            
        except Exception as e:
            print(f"✗ Error: {e}")
            results.append({
                'name': config['name'],
                'success': False,
                'error': str(e)
            })
        
        # Restore environment
        for key in config['env'].keys():
            if original_env[key] is not None:
                os.environ[key] = original_env[key]
            else:
                os.environ.pop(key, None)
    
    return results

def main():
    print("GPU Acceleration Debug Test")
    print("=" * 50)
    
    # Set base environment
    os.environ['LD_LIBRARY_PATH'] = '/home/john/src/talkie/lib/python3.12/site-packages/onnxruntime/capi:' + os.environ.get('LD_LIBRARY_PATH', '')
    
    # Test 1: Direct ONNX Runtime with fixed shapes
    print("PHASE 1: Direct ONNX Runtime Test")
    onnx_success = test_fixed_batch_size()
    
    # Test 2: Sherpa-ONNX with different configurations  
    print("\n" + "=" * 50)
    print("PHASE 2: Sherpa-ONNX Configuration Tests")
    results = test_sherpa_onnx_different_providers()
    
    # Results
    print("\n" + "=" * 50)
    print("FINAL RESULTS")
    print("=" * 50)
    
    print(f"Direct ONNX Runtime: {'✓ SUCCESS' if onnx_success else '✗ FAILED'}")
    
    print("\nSherpa-ONNX Results:")
    successful_configs = []
    for result in results:
        if result['success']:
            print(f"✓ {result['name']}")
            print(f"   Init: {result['init_time']:.3f}s, Process: {result['per_chunk_ms']:.2f}ms/chunk")
            successful_configs.append(result)
        else:
            print(f"✗ {result['name']}: {result.get('error', 'Unknown error')}")
    
    if successful_configs:
        best_config = min(successful_configs, key=lambda x: x['per_chunk_ms'])
        print(f"\n🏆 Best performing: {best_config['name']}")
        print(f"    {best_config['per_chunk_ms']:.2f}ms per chunk")

if __name__ == "__main__":
    main()