#!/home/john/src/talkie/bin/python3

"""
Test script for the modular Talkie architecture
"""

import sys

# Global imports for testing
try:
    from config_manager import ConfigManager
    from audio_manager import AudioManager
    from text_processor import TextProcessor, ProcessingState
    from keyboard_simulator import KeyboardSimulator
    from gui_manager import TalkieGUI
    imports_successful = True
except Exception as import_error:
    imports_successful = False
    import_error_msg = str(import_error)

def test_imports():
    """Test that all modules can be imported successfully"""
    if imports_successful:
        print("Testing imports...")
        print("✓ ConfigManager imported successfully")
        print("✓ AudioManager imported successfully")
        print("✓ TextProcessor imported successfully")
        print("✓ KeyboardSimulator imported successfully")
        print("✓ TalkieGUI imported successfully")
        print("\nAll modules imported successfully!")
        return True
    else:
        print(f"✗ Import error: {import_error_msg}")
        return False

def test_config_manager():
    """Test basic ConfigManager functionality"""
    try:
        print("\nTesting ConfigManager...")
        config_manager = ConfigManager()
        config = config_manager.load_config()
        print(f"✓ Config loaded: {len(config)} parameters")
        return True
    except Exception as e:
        print(f"✗ ConfigManager error: {e}")
        return False

def test_text_processor():
    """Test basic TextProcessor functionality"""
    try:
        print("\nTesting TextProcessor...")
        processor = TextProcessor()
        
        # Test number word detection
        assert processor.is_number_word("five") == True
        assert processor.is_number_word("hello") == False
        print("✓ Number word detection working")
        
        # Test state management
        assert processor.processing_state == ProcessingState.NORMAL
        print("✓ State management working")
        
        return True
    except Exception as e:
        print(f"✗ TextProcessor error: {e}")
        return False

def test_audio_manager():
    """Test basic AudioManager functionality"""
    try:
        print("\nTesting AudioManager...")
        audio_manager = AudioManager()
        
        # Test device listing (this should work even without audio hardware)
        devices = audio_manager.list_audio_devices()
        print(f"✓ Audio device listing working ({len(devices)} devices found)")
        
        return True
    except Exception as e:
        print(f"✗ AudioManager error: {e}")
        return False

def main():
    """Run all tests"""
    print("Talkie Modular Architecture Test")
    print("=" * 40)
    
    all_passed = True
    
    # Test imports
    if not test_imports():
        all_passed = False
    
    # Test individual components
    if not test_config_manager():
        all_passed = False
    
    if not test_text_processor():
        all_passed = False
    
    if not test_audio_manager():
        all_passed = False
    
    print("\n" + "=" * 40)
    if all_passed:
        print("✓ All tests passed! Modular architecture is working correctly.")
        return 0
    else:
        print("✗ Some tests failed. Please check the errors above.")
        return 1

if __name__ == "__main__":
    sys.exit(main())