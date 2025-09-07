#!/home/john/src/talkie/bin/python3

import json
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

DEFAULT_MODEL_PATH = "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"

CONFIG_FILE = Path.home() / ".talkie.conf"
DEFAULT_CONFIG = {
    "audio_device": "pulse",
    "voice_threshold": 50.0,
    "silence_trailing_duration": 0.5,
    "speech_timeout": 3.0,
    "lookback_frames": 10,
    "engine": "vosk",
    "model_path": DEFAULT_MODEL_PATH,
    "window_x": 100,
    "window_y": 100,
    "bubble_enabled": False,
    "bubble_silence_timeout": 3.0,
    "raw_mode": False
}

class ConfigManager:
    """Manages configuration file operations and parameter updates"""
    
    def __init__(self):
        self.config_file = CONFIG_FILE
        self.default_config = DEFAULT_CONFIG.copy()
    
    def load_config(self):
        """Load configuration from JSON file, creating default if not exists"""
        try:
            if self.config_file.exists():
                with open(self.config_file, 'r') as f:
                    config = json.load(f)
                logger.info(f"Loaded config from {self.config_file}")
            else:
                config = self.default_config.copy()
                self.save_config(config)
                logger.info(f"Created default config at {self.config_file}")
            
            return config
            
        except Exception as e:
            logger.error(f"Error loading config: {e}")
            return self.default_config.copy()

    def save_config(self, config):
        """Save configuration to JSON file"""
        try:
            with open(self.config_file, 'w') as f:
                json.dump(config, f, indent=2)
            logger.debug(f"Saved config to {self.config_file}")
        except Exception as e:
            logger.error(f"Error saving config: {e}")

    def update_config_param(self, key, value):
        """Update a single parameter in the config file"""
        config = self.load_config()
        config[key] = value
        self.save_config(config)
        logger.debug(f"Updated config: {key} = {value}")
    
    def get_config_value(self, key, default=None):
        """Get a specific configuration value"""
        config = self.load_config()
        return config.get(key, default)