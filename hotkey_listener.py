import evdev
from select import select
from transcription import toggle_transcription

def listen_for_hotkey():
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    devices = {dev.fd: dev for dev in devices}
    
    meta_pressed = False
    
    while True:
        r, w, x = select(devices, [], [])
        for fd in r:
            for event in devices[fd].read():
                if event.type == evdev.ecodes.EV_KEY:
                    key_event = evdev.categorize(event)
                    
                    # Check for Meta (Super) key
                    if key_event.scancode == 125:  # Left Meta key
                        meta_pressed = key_event.keystate in (key_event.key_down, key_event.key_hold)
                    
                    # Check for 'E' key press while Meta is held down
                    if key_event.scancode == 18 and key_event.keycode == 'KEY_E':
                        if meta_pressed and key_event.keystate == key_event.key_up:
                            toggle_transcription()
                            print("Hotkey pressed. Transcription toggled.")
