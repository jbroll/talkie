#!/home/john/src/talkie/bin/python3

import openvino as ov
import numpy as np
import time

def test_batch_performance():
    """Test OpenVINO models with different batch sizes to find optimal GPU performance"""
    
    print("Testing OpenVINO Batch Performance")
    print("=" * 50)
    
    core = ov.Core()
    
    # Load and compile decoder model (simpler to test)
    model = core.read_model('models/sherpa-onnx-openvino/decoder-int8.xml')
    compiled_gpu = core.compile_model(model, 'GPU')
    compiled_cpu = core.compile_model(model, 'CPU')
    
    print(f"Decoder input shape: {[str(inp.get_partial_shape()) for inp in model.inputs]}")
    
    # Test different batch sizes
    batch_sizes = [1, 2, 4, 8, 16, 32, 64]
    
    results = []
    
    for batch_size in batch_sizes:
        print(f"\\nTesting batch size: {batch_size}")
        
        # Create input tensor with current batch size
        # Decoder expects [batch_size, 2] based on shape [?,2]
        input_tensor = np.random.randn(batch_size, 2).astype(np.float32)
        inputs = {model.inputs[0].get_any_name(): input_tensor}
        
        # GPU performance
        try:
            # Warmup
            for _ in range(5):
                result = compiled_gpu(inputs)
            
            # Benchmark
            start_time = time.time()
            iterations = 50
            for _ in range(iterations):
                result = compiled_gpu(inputs)
            gpu_time = (time.time() - start_time) / iterations
            gpu_throughput = batch_size / gpu_time  # samples per second
            
        except Exception as e:
            print(f"  GPU failed: {e}")
            gpu_time = float('inf')
            gpu_throughput = 0
        
        # CPU performance
        try:
            # Warmup
            for _ in range(5):
                result = compiled_cpu(inputs)
            
            # Benchmark
            start_time = time.time()
            iterations = 50
            for _ in range(iterations):
                result = compiled_cpu(inputs)
            cpu_time = (time.time() - start_time) / iterations
            cpu_throughput = batch_size / cpu_time  # samples per second
            
        except Exception as e:
            print(f"  CPU failed: {e}")
            cpu_time = float('inf')
            cpu_throughput = 0
        
        # Calculate speedup
        speedup = gpu_time / cpu_time if cpu_time > 0 else 0
        
        results.append({
            'batch_size': batch_size,
            'gpu_time': gpu_time * 1000,  # Convert to ms
            'cpu_time': cpu_time * 1000,
            'gpu_throughput': gpu_throughput,
            'cpu_throughput': cpu_throughput,
            'speedup': 1/speedup if speedup > 0 else 0
        })
        
        print(f"  GPU: {gpu_time*1000:.2f}ms ({gpu_throughput:.0f} samples/s)")
        print(f"  CPU: {cpu_time*1000:.2f}ms ({cpu_throughput:.0f} samples/s)")
        print(f"  GPU Speedup: {1/speedup:.2f}x" if speedup > 0 else "  GPU Speedup: N/A")
    
    print("\\n" + "=" * 50)
    print("BATCH PERFORMANCE SUMMARY")
    print("=" * 50)
    print(f"{'Batch':>5} | {'GPU (ms)':>8} | {'CPU (ms)':>8} | {'GPU Speedup':>10} | {'Best':>4}")
    print("-" * 50)
    
    best_speedup = 0
    best_batch = 0
    
    for result in results:
        speedup_str = f"{result['speedup']:.2f}x" if result['speedup'] > 0 else "N/A"
        is_best = "★" if result['speedup'] > best_speedup else ""
        
        if result['speedup'] > best_speedup:
            best_speedup = result['speedup']
            best_batch = result['batch_size']
        
        print(f"{result['batch_size']:5d} | {result['gpu_time']:8.2f} | {result['cpu_time']:8.2f} | {speedup_str:>10} | {is_best:>4}")
    
    print("\\n" + "=" * 50)
    print("CONCLUSIONS")
    print("=" * 50)
    
    if best_speedup > 1.2:
        print(f"✅ GPU acceleration achieved at batch size {best_batch}")
        print(f"   Best speedup: {best_speedup:.2f}x")
        print("   GPU is beneficial for larger batch processing")
    elif best_speedup > 0.8:
        print(f"⚠️  Marginal GPU benefit at batch size {best_batch}")
        print(f"   Best speedup: {best_speedup:.2f}x")
        print("   CPU and GPU performance are similar")
    else:
        print("❌ CPU consistently outperforms GPU")
        print("   For real-time single-stream processing, CPU is optimal")
    
    return best_speedup > 1.2

if __name__ == "__main__":
    success = test_batch_performance()
    
    if success:
        print("\\n🎉 GPU acceleration can be beneficial for batch processing!")
    else:
        print("\\n💡 Stick with CPU for optimal single-stream performance")
        print("   This is actually a good result - CPU optimization is excellent!")