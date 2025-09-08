#!/usr/bin/env python3
"""
Test Vosk parameters and what methods are available
"""

import sys
import os
sys.path.append('src')

try:
    import vosk
    print("✓ Vosk imported successfully")
    vosk.SetLogLevel(-1)
    
    # Test model loading
    model_path = "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
    if not os.path.exists(model_path):
        print(f"✗ Model not found at {model_path}")
        exit(1)
    
    print(f"Loading model from {model_path}")
    model = vosk.Model(model_path)
    recognizer = vosk.KaldiRecognizer(model, 16000)
    
    print("\n=== Available Vosk KaldiRecognizer Methods ===")
    methods = [method for method in dir(recognizer) if not method.startswith('_')]
    for method in sorted(methods):
        print(f"  {method}")
    
    print("\n=== Testing Parameter Methods ===")
    
    # Test SetWords
    try:
        recognizer.SetWords(True)
        print("✓ SetWords(True) - SUCCESS")
    except Exception as e:
        print(f"✗ SetWords failed: {e}")
    
    # Test SetMaxAlternatives
    try:
        if hasattr(recognizer, 'SetMaxAlternatives'):
            recognizer.SetMaxAlternatives(0)
            print("✓ SetMaxAlternatives(0) - SUCCESS")
        else:
            print("✗ SetMaxAlternatives - NOT AVAILABLE")
    except Exception as e:
        print(f"✗ SetMaxAlternatives failed: {e}")
    
    # Test beam parameters
    beam_methods = ['SetBeam', 'SetLatticeBeam', 'SetMaxActive', 'SetMinActive']
    for method in beam_methods:
        try:
            if hasattr(recognizer, method):
                print(f"✓ {method} - AVAILABLE")
            else:
                print(f"✗ {method} - NOT AVAILABLE")
        except Exception as e:
            print(f"✗ {method} failed: {e}")
    
    print("\n=== Model Configuration ===")
    # Check if model has a config file
    config_file = os.path.join(model_path, "conf", "model.conf")
    if os.path.exists(config_file):
        print(f"✓ Model config found: {config_file}")
        with open(config_file, 'r') as f:
            print("Config contents:")
            print(f.read())
    else:
        print(f"✗ No model config at: {config_file}")
        
        # Check for other config files
        conf_dir = os.path.join(model_path, "conf")
        if os.path.exists(conf_dir):
            print(f"Config directory contents:")
            for file in os.listdir(conf_dir):
                print(f"  {file}")
        else:
            print("No conf directory found")
    
except ImportError:
    print("✗ Vosk not available")
    exit(1)
except Exception as e:
    print(f"✗ Error: {e}")
    exit(1)