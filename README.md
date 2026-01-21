# WM8960 Audio HAT Drivers

## Overview
The WM8960 Audio HAT Drivers provide necessary software support for interfacing with the WM8960 audio codec, offering high-quality audio playback and recording capabilities for Raspberry Pi and similar platforms.

## Table of Contents
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)

## Installation

### Prerequisites
- Raspberry Pi or compatible device
- Raspbian or another Linux distribution installed
- Kernel headers for your Linux version

### Steps
1. **Clone the repository**:
   ```bash
   git clone https://github.com/MJD19994/WM8960_AudioHAT_Drivers.git
   cd WM8960_AudioHAT_Drivers
   ```
2. **Install dependencies**:
   ```bash
   sudo apt-get update
   sudo apt-get install build-essential git
   ```
3. **Compile the drivers**:
   ```bash
   make
   ```
4. **Install the drivers**:
   ```bash
   sudo make install
   ```

## Configuration

### Device Tree Setup
To use the WM8960 codec, you might need to set up the Device Tree (DT) overlay. Edit the `/boot/config.txt` file to add:
```bash
dtoverlay=wm8960-audio-hat
```

### ALSA Configuration
Create or edit the ALSA configuration file:
```bash
sudo nano /etc/asound.conf
```
Add the following configuration:
```plaintext
pcm.!default {
   type hw
   card 0
}

ctl.!default {
   type hw
   card 0
}
```

## Usage
After installation and configuration, you can test audio playback using the following command:
```bash
aplay /path/to/audio/file.wav
```

## Troubleshooting
- If you encounter issues with playback, ensure that the drivers are properly installed and check the logs for errors.
- Ensure that the audio file format is supported by ALSA.

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.