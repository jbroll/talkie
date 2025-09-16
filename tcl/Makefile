# Makefile for Talkie Tcl Edition
# Uses existing PortAudio and Vosk bindings

# Configuration
TCL_VERSION = 8.6
PREFIX = /usr/local

# Directories
PA_DIR = pa
VOSK_DIR = vosk
BUILD_DIR = build

.PHONY: all clean install test deps check-deps

all: check-deps $(BUILD_DIR) build-packages

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Check dependencies
check-deps:
	@echo "Checking dependencies..."
	@which tclsh > /dev/null || (echo "ERROR: tclsh not found" && exit 1)
	@pkg-config --exists portaudio-2.0 || (echo "ERROR: PortAudio not found" && exit 1)
	@test -f ~/.local/lib/libvosk.so || (echo "ERROR: Vosk library not found in ~/.local/lib" && exit 1)
	@echo "All dependencies found."

# Build existing packages
build-packages: $(BUILD_DIR)
	@echo "Building PortAudio package..."
	cd $(PA_DIR) && TCLLIBPATH="$$HOME/.local/lib" tclsh pa.tcl
	@echo "Building Vosk package..."
	cd $(VOSK_DIR) && TCLLIBPATH="$$HOME/.local/lib" tclsh vosk.tcl
	@echo "Build complete."

# Install dependencies on Ubuntu/Debian
deps:
	@echo "Installing dependencies..."
	sudo apt-get update
	sudo apt-get install -y \
		tcl$(TCL_VERSION)-dev \
		tk$(TCL_VERSION)-dev \
		critcl \
		libportaudio2 \
		libportaudio19-dev \
		pkg-config \
		build-essential
	@echo "Installing Vosk..."
	@if ! ldconfig -p | grep -q libvosk; then \
		echo "Vosk not found. Installing from pip..."; \
		pip3 install vosk || echo "Please install Vosk manually"; \
	fi
	@echo "Dependencies installation complete."

# Test the build
test: all
	@echo "Testing PortAudio package..."
	cd $(PA_DIR) && tclsh test_pa.tcl
	@echo "Testing Vosk package..."
	cd $(VOSK_DIR) && tclsh -c "lappend auto_path lib; package require vosk; puts {Vosk package loaded successfully}"
	@echo "Running integration test..."
	@tclsh test_integration.tcl

# Run the application
run: all
	./talkie.tcl

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(PA_DIR)/lib
	rm -rf $(VOSK_DIR)/lib
	find . -name "*.o" -delete
	find . -name "*.so" -delete

# Install system-wide
install: all
	@echo "Installing Talkie Tcl Edition..."
	sudo mkdir -p $(PREFIX)/bin
	sudo mkdir -p $(PREFIX)/lib/talkie-tcl
	sudo cp talkie_main.tcl $(PREFIX)/bin/talkie-tcl
	sudo chmod +x $(PREFIX)/bin/talkie-tcl
	sudo cp -r . $(PREFIX)/lib/talkie-tcl/
	@echo "Installation complete. Run with: talkie-tcl"

# Development mode - run with automatic rebuilds
dev: all
	@echo "Starting development mode..."
	@while true; do \
		inotifywait -q -e modify,create,delete -r . --exclude '\.git|build' && \
		make build-packages && \
		echo "Rebuilt at $$(date)"; \
	done

# Create desktop entry
desktop-entry:
	@echo "Creating desktop entry..."
	@echo "[Desktop Entry]" > talkie-tcl.desktop
	@echo "Version=1.0" >> talkie-tcl.desktop
	@echo "Type=Application" >> talkie-tcl.desktop
	@echo "Name=Talkie Tcl" >> talkie-tcl.desktop
	@echo "Comment=Speech-to-text application written in Tcl" >> talkie-tcl.desktop
	@echo "Exec=$(PREFIX)/bin/talkie-tcl" >> talkie-tcl.desktop
	@echo "Icon=audio-input-microphone" >> talkie-tcl.desktop
	@echo "Terminal=false" >> talkie-tcl.desktop
	@echo "Categories=AudioVideo;Audio;" >> talkie-tcl.desktop
	@echo "Keywords=speech;recognition;voice;transcription;" >> talkie-tcl.desktop
	sudo cp talkie-tcl.desktop /usr/share/applications/
	sudo update-desktop-database

# Show help
help:
	@echo "Talkie Tcl Edition Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Build everything (default)"
	@echo "  deps         - Install system dependencies"
	@echo "  check-deps   - Check if dependencies are installed"
	@echo "  test         - Test the build"
	@echo "  run          - Build and run the application"
	@echo "  clean        - Clean build artifacts"
	@echo "  install      - Install system-wide"
	@echo "  dev          - Development mode with auto-rebuild"
	@echo "  desktop-entry- Create desktop entry"
	@echo "  help         - Show this help"
	@echo ""
	@echo "Dependencies:"
	@echo "  - Tcl/Tk $(TCL_VERSION)"
	@echo "  - Eigen3"
	@echo "  - PortAudio"
	@echo "  - Vosk"
	@echo "  - critcl"
