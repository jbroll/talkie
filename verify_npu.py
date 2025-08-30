#!/usr/bin/env python3
import sys
import logging

# Set up basic logging for the script
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')

def check_npu_requirements():
    """Check if NPU requirements are met"""
    requirements = {
        "openvino": False,
        "openvino-genai": False,
        "optimum": False,
        "npu_device": False
    }
    
    try:
        import openvino
        requirements["openvino"] = True
        print("✓ OpenVINO available")
    except ImportError:
        print("✗ OpenVINO not available")
        
    try:
        import openvino_genai
        requirements["openvino-genai"] = True
        print("✓ OpenVINO GenAI available")
    except ImportError:
        print("✗ OpenVINO GenAI not available")
        
    try:
        import optimum
        requirements["optimum"] = True
        print("✓ Optimum available")
    except ImportError:
        print("✗ Optimum not available")
        
    # Check NPU device availability
    try:
        import openvino as ov
        core = ov.Core()
        devices = core.available_devices
        
        npu_devices = [d for d in devices if "NPU" in d]
        if npu_devices:
            print(f"✓ Intel NPU detected: {npu_devices}")
            requirements["npu_device"] = True
        else:
            print("✗ No Intel NPU detected")
            print(f"Available devices: {devices}")
            requirements["npu_device"] = False
            
    except ImportError:
        print("✗ Cannot detect NPU - OpenVINO not available")
        requirements["npu_device"] = False
    except Exception as e:
        print(f"✗ Error detecting NPU: {e}")
        requirements["npu_device"] = False
        
    return requirements

def main():
    print("Checking NPU requirements for Talkie OpenVINO Whisper...")
    print("=" * 60)
    
    requirements = check_npu_requirements()
    
    print("\nRequirement Summary:")
    all_met = True
    for req, status in requirements.items():
        status_str = "✓" if status else "✗"
        print(f"  {status_str} {req}")
        if not status:
            all_met = False
    
    print("=" * 60)
    if all_met:
        print("✓ All NPU requirements met! OpenVINO Whisper with NPU can be used.")
        return 0
    else:
        missing = [k for k, v in requirements.items() if not v]
        print(f"✗ Missing requirements: {', '.join(missing)}")
        print("\nTo install missing dependencies:")
        print("pip install openvino openvino-genai optimum[openvino]")
        
        if not requirements["npu_device"]:
            print("\nNPU Hardware Requirements:")
            print("- Intel Core Ultra processor (Meteor Lake or Arrow Lake)")
            print("- Proper NPU drivers installed")
            print("- Check: lsmod | grep intel_vpu")
            
        return 1

if __name__ == "__main__":
    sys.exit(main())