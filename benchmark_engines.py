#!/home/john/src/talkie/bin/python3

import os
import sys
import subprocess
import time
import json
from pathlib import Path

def run_benchmark(test_name, command, description):
    """Run a single benchmark and capture results"""
    print(f"\n{'='*60}")
    print(f"BENCHMARK: {test_name}")
    print(f"DESCRIPTION: {description}")
    print(f"COMMAND: {command}")
    print(f"{'='*60}")
    
    start_time = time.time()
    
    try:
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=120  # 2 minute timeout
        )
        
        end_time = time.time()
        duration = end_time - start_time
        
        print(f"Exit Code: {result.returncode}")
        print(f"Duration: {duration:.2f} seconds")
        
        if result.stdout:
            print(f"STDOUT:\n{result.stdout}")
        if result.stderr:
            print(f"STDERR:\n{result.stderr}")
            
        return {
            'test_name': test_name,
            'description': description,
            'command': command,
            'exit_code': result.returncode,
            'duration': duration,
            'stdout': result.stdout,
            'stderr': result.stderr,
            'success': result.returncode == 0
        }
        
    except subprocess.TimeoutExpired:
        print(f"TIMEOUT: Test exceeded 120 seconds")
        return {
            'test_name': test_name,
            'description': description,
            'command': command,
            'exit_code': -1,
            'duration': 120.0,
            'stdout': '',
            'stderr': 'Test timed out after 120 seconds',
            'success': False
        }
    except Exception as e:
        print(f"ERROR: {e}")
        return {
            'test_name': test_name,
            'description': description,
            'command': command,
            'exit_code': -2,
            'duration': 0.0,
            'stdout': '',
            'stderr': str(e),
            'success': False
        }

def main():
    """Run comprehensive engine benchmarks"""
    
    # Ensure we're in the right directory
    os.chdir('/home/john/src/talkie')
    
    # Test audio file
    test_audio = "models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26/test_wavs/0.wav"
    
    if not Path(test_audio).exists():
        print(f"ERROR: Test audio file not found: {test_audio}")
        sys.exit(1)
    
    # Environment setup for GPU acceleration
    gpu_env = {
        'LD_LIBRARY_PATH': '/home/john/src/talkie/lib/python3.12/site-packages/onnxruntime/capi:' + os.environ.get('LD_LIBRARY_PATH', ''),
        'ORT_PROVIDERS': 'OpenVINOExecutionProvider,CPUExecutionProvider',
        'OV_DEVICE': 'GPU',
        'OV_GPU_ENABLE_BINARY_CACHE': '1'
    }
    
    # Build environment command prefix
    gpu_env_cmd = ' '.join([f'{k}={v}' for k, v in gpu_env.items()])
    
    benchmarks = [
        # Sherpa-ONNX with Intel ARC Graphics GPU acceleration
        {
            'name': 'Sherpa-ONNX GPU (Intel ARC)',
            'command': f'{gpu_env_cmd} time ./test_speech_engines.py {test_audio} --test-sherpa --verbose',
            'description': 'Sherpa-ONNX with OpenVINO GPU acceleration on Intel ARC Graphics'
        },
        
        # Sherpa-ONNX CPU-only (disable OpenVINO)
        {
            'name': 'Sherpa-ONNX CPU',
            'command': f'DISABLE_OPENVINO=1 time ./test_speech_engines.py {test_audio} --test-sherpa --verbose',
            'description': 'Sherpa-ONNX with CPU processing only (OpenVINO disabled)'
        },
        
        # Vosk baseline
        {
            'name': 'Vosk CPU',
            'command': f'time ./test_speech_engines.py {test_audio} --test-vosk --verbose',
            'description': 'Vosk speech recognition with CPU processing'
        },
        
        # Combined test (both engines)
        {
            'name': 'Sherpa-ONNX + Vosk',
            'command': f'{gpu_env_cmd} time ./test_speech_engines.py {test_audio} --test-sherpa --test-vosk --verbose',
            'description': 'Both Sherpa-ONNX (GPU) and Vosk for comparison'
        }
    ]
    
    results = []
    
    print("Starting Talkie Engine Performance Benchmarks")
    print(f"Test Audio: {test_audio}")
    print(f"Hardware: Intel Core Ultra 7 155H + Intel ARC Graphics")
    print(f"Timestamp: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    
    for benchmark in benchmarks:
        result = run_benchmark(
            benchmark['name'],
            benchmark['command'], 
            benchmark['description']
        )
        results.append(result)
        
        # Brief pause between tests
        time.sleep(2)
    
    # Summary
    print(f"\n{'='*60}")
    print("BENCHMARK SUMMARY")
    print(f"{'='*60}")
    
    for result in results:
        status = "PASS" if result['success'] else "FAIL"
        print(f"{result['test_name']:25} | {status:4} | {result['duration']:6.2f}s")
    
    # Save detailed results to JSON
    results_file = f"benchmark_results_{int(time.time())}.json"
    with open(results_file, 'w') as f:
        json.dump({
            'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
            'hardware': 'Intel Core Ultra 7 155H + Intel ARC Graphics',
            'test_audio': test_audio,
            'results': results
        }, f, indent=2)
    
    print(f"\nDetailed results saved to: {results_file}")
    
    return 0 if all(r['success'] for r in results) else 1

if __name__ == "__main__":
    sys.exit(main())