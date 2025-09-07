# @imports
import json
import threading
import time
from pathlib import Path
import select
import os
from addict import Dict

# @file_monitor
class JSONFileMonitor:
    """Monitor a file for changes and parse JSON content"""
    
    def __init__(self, file_path, callback):
        self.file_path = Path(file_path)
        self.callback = callback
        self.running = False
        self.monitor_thread = None
        self.last_data = None
        self.last_mtime = None
        
    def start(self):
        """Start monitoring the file"""
        # Read initial state
        self._read_and_notify()
        
        self.running = True
        self.monitor_thread = threading.Thread(target=self._monitor_file, daemon=True)
        self.monitor_thread.start()
        
    def stop(self):
        """Stop monitoring the file"""
        self.running = False
        if self.monitor_thread:
            self.monitor_thread.join(timeout=1.0)
            
    def _read_and_notify(self):
        """Read file content and notify callback if changed"""
        try:
            if self.file_path.exists():
                # Check if file was modified
                current_mtime = self.file_path.stat().st_mtime
                if current_mtime != self.last_mtime:
                    self.last_mtime = current_mtime
                    
                    with open(self.file_path, 'r') as f:
                        content = f.read().strip()
                        if content:
                            data = json.loads(content)
                            if data != self.last_data:
                                self.last_data = data
                                self.callback(Dict(data))
        except json.JSONDecodeError as e:
            print(f"Error parsing JSON from {self.file_path}: {e}")
        except Exception as e:
            print(f"Error reading {self.file_path}: {e}")
            
    def _monitor_file(self):
        """Monitor file changes using simple polling"""
        while self.running:
            self._read_and_notify()
            time.sleep(0.1)  # Check every 100ms
