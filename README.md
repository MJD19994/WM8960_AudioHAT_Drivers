# WM8960 AudioHAT Drivers

## Overview
The WM8960 AudioHAT Drivers provide support for the WM8960 audio codec on HAT-formatted boards. This guide explains how to install, configure, and verify the drivers.

## Issues Fixed Table
| Issue ID | Description                              | Status   |
|----------|------------------------------------------|----------|
| #1       | Fixed initialization failure.            | Resolved |
| #2       | Improved audio quality on playback.     | Resolved |
| #3       | Addressed compatibility with Python 3.6 | Resolved |

## Prerequisites

### Step 0: System Updates
Make sure your system is up-to-date by running the following commands:
```bash
sudo apt update && sudo apt upgrade -y
```

### Step 1: Git Prerequisites
Ensure that you have Git installed. If not, install it using:
```bash
sudo apt install git -y
```

### Step 2: Build Tools Installation
To build the drivers, install the necessary build tools:
```bash
sudo apt install build-essential -y
```

## Full Installation Steps
1. Clone the repository:
    ```bash
    git clone https://github.com/MJD19994/WM8960_AudioHAT_Drivers.git
    cd WM8960_AudioHAT_Drivers
    ```
2. Run the install script:
    ```bash
    sudo ./install.sh
    ```

## Verification Procedures
After installation, you can verify the setup by running:
```bash
speaker-test -c2 -twav
```
This will test the stereo output to ensure everything is functioning correctly.

## Configuration Explanations
Modify the configuration file located at `/etc/wm8960.conf` to customize settings for your specific needs.

## Dynamic Loading Explanation
The drivers support dynamic loading. You can load the module using:
```bash
sudo modprobe wm8960
```

## Advanced Configuration
For advanced users, you can set parameters in `/etc/modprobe.d/wm8960.conf` to tweak performance settings.

## Troubleshooting References
If you encounter issues, refer to the troubleshooting section in the [official documentation](URL_TO_DOCUMENTATION).

## Uninstallation
To uninstall the drivers, run:
```bash
sudo make uninstall
```

## License Information
The WM8960 AudioHAT Drivers are released under the MIT License. See the LICENSE file for details.