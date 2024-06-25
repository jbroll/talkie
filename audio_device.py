import sounddevice as sd
from logger import get_logger

logger = get_logger()

def list_audio_devices():
    logger.info("Available audio input devices:")
    devices = sd.query_devices()
    for i, device in enumerate(devices):
        if device['max_input_channels'] > 0:
            logger.info(f"{i}: {device['name']}")
    return devices

def get_supported_samplerates(device_id):
    device_info = sd.query_devices(device_id, 'input')
    try:
        supported_rates = [
            int(rate) for rate in device_info['default_samplerate'].split(',')
        ]
    except AttributeError:
        supported_rates = [int(device_info['default_samplerate'])]
    
    logger.debug(f"Supported sample rates for this device: {supported_rates}")
    return supported_rates

def select_audio_device(device_substring=None):
    devices = list_audio_devices()
    
    if device_substring:
        matching_devices = [
            (i, device) for i, device in enumerate(devices)
            if device['max_input_channels'] > 0 and device_substring.lower() in device['name'].lower()
        ]
        
        if matching_devices:
            if len(matching_devices) > 1:
                logger.info("Multiple matching devices found:")
                for i, device in matching_devices:
                    logger.info(f"{i}: {device['name']}")
                device_id = int(input("Enter the number of the input device you want to use: "))
            else:
                device_id = matching_devices[0][0]
            
            device_info = devices[device_id]
            logger.info(f"Selected device: {device_info['name']}")
        else:
            logger.error(f"No device matching '{device_substring}' found.")
            return None, None
    else:
        while True:
            try:
                device_id = int(input("Enter the number of the input device you want to use: "))
                device_info = devices[device_id]
                if device_info['max_input_channels'] > 0:
                    break
                else:
                    logger.error("Invalid input device. Please choose a device with input channels.")
            except (ValueError, IndexError):
                logger.error("Invalid input. Please enter a valid device number.")
    
    supported_rates = get_supported_samplerates(device_id)
    if not supported_rates:
        logger.error("No supported sample rates found for this device.")
        return None, None
    
    preferred_rates = [r for r in supported_rates if r <= 16000]
    if preferred_rates:
        samplerate = max(preferred_rates)
    else:
        samplerate = min(supported_rates)
    logger.info(f"Selected sample rate: {samplerate} Hz")
    
    return device_id, samplerate
