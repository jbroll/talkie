#!/home/john/src/talkie/bin/python3

import openvino as ov
import numpy as np
import time

def test_openvino_models_performance():
    """Test OpenVINO IR models directly for GPU performance"""
    
    print("Testing OpenVINO IR Models with GPU Acceleration")
    print("=" * 60)
    
    core = ov.Core()
    print(f"Available devices: {core.available_devices}")
    
    if 'GPU' not in core.available_devices:
        print("❌ GPU not available")
        return False
    
    gpu_name = core.get_property('GPU', 'FULL_DEVICE_NAME')
    print(f"GPU: {gpu_name}")
    
    # Load models
    models = {
        'encoder': 'models/sherpa-onnx-openvino/encoder-int8.xml',
        'decoder': 'models/sherpa-onnx-openvino/decoder-int8.xml', 
        'joiner': 'models/sherpa-onnx-openvino/joiner-int8.xml'
    }
    
    compiled_models = {}
    
    print("\\n" + "=" * 60)
    print("MODEL COMPILATION")
    print("=" * 60)
    
    # Compile models for both CPU and GPU
    for name, model_path in models.items():
        print(f"\\nTesting {name.upper()} model...")
        
        try:
            # Load model
            model = core.read_model(model_path)
            print(f"  Inputs: {len(model.inputs)}")
            
            # Compile for GPU
            start_time = time.time()
            compiled_gpu = core.compile_model(model, 'GPU')
            gpu_compile_time = time.time() - start_time
            
            # Compile for CPU comparison
            start_time = time.time()
            compiled_cpu = core.compile_model(model, 'CPU')
            cpu_compile_time = time.time() - start_time
            
            compiled_models[name] = {
                'model': model,
                'gpu': compiled_gpu,
                'cpu': compiled_cpu
            }
            
            print(f"  ✓ GPU compilation: {gpu_compile_time:.3f}s")
            print(f"  ✓ CPU compilation: {cpu_compile_time:.3f}s")
            
        except Exception as e:
            print(f"  ❌ {name} failed: {e}")
            return False
    
    print("\\n" + "=" * 60)
    print("PERFORMANCE TESTING")
    print("=" * 60)
    
    # Test encoder performance (most computationally intensive)
    if 'encoder' in compiled_models:
        print("\\nTesting ENCODER inference performance...")
        
        model = compiled_models['encoder']['model']
        
        # Create sample inputs matching the expected shapes
        # Using fixed batch size of 1 as converted
        sample_inputs = {}
        for inp in model.inputs:
            partial_shape = inp.get_partial_shape()
            
            # Convert partial shape to fixed shape
            fixed_shape = []
            for dim in partial_shape:
                if dim.is_dynamic:  # Dynamic dimension
                    fixed_shape.append(1)  # Use batch size 1
                else:
                    fixed_shape.append(dim.get_length())
            
            # Create sample data
            sample_inputs[inp.get_any_name()] = np.random.randn(*fixed_shape).astype(np.float32)
        
        print(f"  Created {len(sample_inputs)} input tensors")
        
        # Test GPU performance
        try:
            compiled_gpu = compiled_models['encoder']['gpu']
            
            # Warmup
            for _ in range(5):
                result = compiled_gpu(sample_inputs)
            
            # Benchmark
            start_time = time.time()
            for _ in range(20):
                result = compiled_gpu(sample_inputs)
            gpu_time = (time.time() - start_time) / 20
            
            print(f"  ✓ GPU inference: {gpu_time*1000:.2f}ms per iteration")
            
        except Exception as e:
            print(f"  ❌ GPU inference failed: {e}")
            gpu_time = float('inf')
        
        # Test CPU performance
        try:
            compiled_cpu = compiled_models['encoder']['cpu']
            
            # Warmup
            for _ in range(5):
                result = compiled_cpu(sample_inputs)
            
            # Benchmark
            start_time = time.time()
            for _ in range(20):
                result = compiled_cpu(sample_inputs)
            cpu_time = (time.time() - start_time) / 20
            
            print(f"  ✓ CPU inference: {cpu_time*1000:.2f}ms per iteration")
            
        except Exception as e:
            print(f"  ❌ CPU inference failed: {e}")
            cpu_time = float('inf')
        
        # Calculate speedup
        if gpu_time != float('inf') and cpu_time != float('inf'):
            speedup = cpu_time / gpu_time
            print(f"  🚀 GPU Speedup: {speedup:.2f}x faster than CPU")
            
            if speedup > 1.2:
                print("  ✅ Significant GPU acceleration achieved!")
                return True
            else:
                print("  ⚠️  Limited GPU acceleration")
                return False
        else:
            print("  ❌ Could not measure performance")
            return False
    
    return False

def main():
    success = test_openvino_models_performance()
    
    print("\\n" + "=" * 60)
    print("FINAL RESULT")
    print("=" * 60)
    
    if success:
        print("🎉 OpenVINO GPU acceleration is WORKING with converted models!")
        print("   Next step: Integrate this into Sherpa-ONNX or create custom pipeline")
    else:
        print("❌ GPU acceleration not achieved or not significant")
        print("   Current CPU performance may be sufficient")

if __name__ == "__main__":
    main()