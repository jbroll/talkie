<h1 style="display: flex; align-items: center;"><img src="icon.svg" alt="Talkie Icon" width="64" height="64" style="margin-right: 15px;"/> Talkie - Chat with your Linux desktop</h1>
<img src="Screenshot%20from%202025-09-07%2015-22-01.png" alt="Talkie Desktop UI" align="right" width="500"/>

Talkie listens to your voice and types what you say. It works with any app on
Linux - email, documents, chat, anywhere you need to type. Speak naturally
and watch your words as they are typed onto the screen.

Uses the Vosk speech recognition engine for accurate, fast transcription that works offline.

<br clear="right"/>

## What it does

- **Real-time speech recognition** - Converts your speech to text as you speak
- **Universal compatibility** - Works with any application that accepts text input
- **Voice command punctuation** - Say punctuation words like "period" or "comma"
- **Automatic number conversion** - Converts spoken numbers to digits ("twenty five" → "25")
- **Dual interface modes** - Choose between full control window or minimal bubble view
- **Persistent configuration** - Remembers your preferences and window positions
- **Offline operation** - No internet required, everything runs locally

## How to use it

### Start it up
```bash
./talkie.sh
```

### Turn listening on and off
```bash
./talkie.sh start     # Start listening
./talkie.sh stop      # Stop listening
./talkie.sh toggle    # Switch on/off
```

## Voice commands you can say

- Say "period" to type a dot (.)
- Say "comma" to type a comma (,)
- Say "question mark" to type (?)
- Say "new line" to press Enter
- Say numbers like "twenty five" and it types 25

## Settings you can change

The program saves your settings in a file called `~/.talkie.conf`. Here's what you can change:

- **energy_threshold**: How loud you need to speak (50 is normal)
- **speech_timeout**: How long to wait before stopping (3 seconds)
- **confidence_threshold**: How sure the program needs to be (280 is good)
- **bubble_enabled**: Use tiny window instead of big one (false = big window)

## What you need

To use Talkie, your computer needs:
- Linux with a desltop (Gnome, KDE, XFCE, ...)
- A microphone
- Python 3.8 or newer

The program will install these parts automatically:
- sounddevice (to hear your voice)
- vosk (to understand your words)
- word2number (to convert "twenty" to "20")

## Installation

```bash
# Go to the talkie folder
cd /home/john/src/talkie

# Install the parts it needs
pip install -r requirements.txt

# Start using it
./talkie.sh
```
