#!/bin/bash

set -e

# Capture script directory at the very start (before any directory changes)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==============================================="
echo "WM8960 Audio HAT Installation Script"
echo "==============================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

echo "Step 1/11: Updating package lists..."
apt-get update

echo ""
echo "Step 2/11: Installing kernel headers..."
apt-get install -y linux-headers-$(uname -r)

echo ""
echo "Step 3/11: Installing required packages..."
apt-get install -y dkms git i2c-tools libasound2-plugins

echo ""
echo "Step 4/11: Compiling and installing wm8960-soundcard kernel module via DKMS..."
# Check if DKMS module is already installed
if dkms status | grep -q "wm8960-soundcard"; then
    echo "DKMS module already installed, removing old version..."
    dkms remove wm8960-soundcard/1.0 --all
fi

# Copy kernel module source from local repository if not present
if [ ! -d "/usr/src/wm8960-soundcard-1.0" ]; then
    echo "Copying WM8960 kernel module source from local repository..."
    
    # Verify local source files exist
    if [ ! -d "$SCRIPT_DIR/kernel_module" ]; then
        echo "Error: kernel_module directory not found in $SCRIPT_DIR"
        exit 1
    fi
    
    # Verify required source files are present
    echo "Verifying source files..."
    required_files=("wm8960.c" "wm8960.h" "wm8960-soundcard.c" "Makefile" "dkms.conf")
    for file in "${required_files[@]}"; do
        if [ ! -f "$SCRIPT_DIR/kernel_module/$file" ]; then
            echo "Error: Required file $file not found in $SCRIPT_DIR/kernel_module/"
            exit 1
        fi
    done
    echo "All required source files present"
    
    # Copy only source files to /usr/src for DKMS (not binary .dtbo files)
    mkdir -p /usr/src/wm8960-soundcard-1.0
    for file in "${required_files[@]}"; do
        cp "$SCRIPT_DIR/kernel_module/$file" /usr/src/wm8960-soundcard-1.0/
    done
    
    echo "Kernel module source files copied successfully"
else
    echo "DKMS source already present in /usr/src/wm8960-soundcard-1.0"
fi

# Add and build DKMS module
echo "Adding module to DKMS..."
dkms add -m wm8960-soundcard -v 1.0 2>/dev/null || echo "Module already added to DKMS"

echo "Building module with DKMS..."
dkms build -m wm8960-soundcard -v 1.0

echo "Installing module with DKMS..."
dkms install -m wm8960-soundcard -v 1.0

echo ""
echo "Step 5/11: Copying device tree overlay..."
# Verify the dtbo file exists in the repository
if [ ! -f "$SCRIPT_DIR/kernel_module/wm8960-soundcard.dtbo" ]; then
    echo "Error: wm8960-soundcard.dtbo not found in $SCRIPT_DIR/kernel_module/"
    exit 1
fi

# Detect boot partition location
if [ -d "/boot/firmware/overlays" ]; then
    BOOT_OVERLAYS="/boot/firmware/overlays"
elif [ -d "/boot/overlays" ]; then
    BOOT_OVERLAYS="/boot/overlays"
else
    # If neither exists, check which boot firmware location is in use
    if [ -d "/boot/firmware" ]; then
        BOOT_OVERLAYS="/boot/firmware/overlays"
        echo "Note: Boot firmware overlays directory not found, will create $BOOT_OVERLAYS"
    else
        BOOT_OVERLAYS="/boot/overlays"
        echo "Note: Boot overlays directory not found, will create $BOOT_OVERLAYS"
    fi
fi

# Create overlays directory if it doesn't exist
mkdir -p "$BOOT_OVERLAYS"

# Copy the device tree overlay
echo "Copying wm8960-soundcard.dtbo to $BOOT_OVERLAYS/..."
cp "$SCRIPT_DIR/kernel_module/wm8960-soundcard.dtbo" "$BOOT_OVERLAYS/"

# Verify the copy was successful
if [ -f "$BOOT_OVERLAYS/wm8960-soundcard.dtbo" ]; then
    echo "Device tree overlay copied successfully"
else
    echo "Error: Failed to copy device tree overlay"
    exit 1
fi

echo ""
echo "Step 6/11: Configuring kernel modules in /etc/modules..."
# Add i2c-dev to /etc/modules if not present
if ! grep -q "^i2c-dev" /etc/modules; then
    echo "i2c-dev" >> /etc/modules
    echo "Added i2c-dev to /etc/modules"
fi

echo ""
echo "Step 7/11: Enabling I2C and I2S in /boot/firmware/config.txt..."
CONFIG_FILE="/boot/firmware/config.txt"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="/boot/config.txt"
fi

# Backup config.txt
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Enable I2C
if ! grep -q "^dtparam=i2c_arm=on" "$CONFIG_FILE"; then
    echo "dtparam=i2c_arm=on" >> "$CONFIG_FILE"
    echo "Enabled I2C in config.txt"
fi

# Enable I2S
if ! grep -q "^dtparam=i2s=on" "$CONFIG_FILE"; then
    echo "dtparam=i2s=on" >> "$CONFIG_FILE"
    echo "Enabled I2S in config.txt"
fi

# Note: We do NOT add dtoverlay=wm8960-soundcard here - loaded dynamically by service
echo "Note: wm8960-soundcard overlay will be loaded dynamically by the systemd service"

echo ""
echo "Step 8/11: Installing ALSA configuration files..."
# Create directory for WM8960 configuration
mkdir -p /etc/wm8960-soundcard

# Copy ALSA configuration files
if [ -f "$SCRIPT_DIR/asound.conf" ]; then
    cp "$SCRIPT_DIR/asound.conf" /etc/wm8960-soundcard/
    echo "Installed asound.conf"
else
    echo "Warning: asound.conf not found in script directory"
fi

if [ -f "$SCRIPT_DIR/wm8960_asound.state" ]; then
    cp "$SCRIPT_DIR/wm8960_asound.state" /etc/wm8960-soundcard/
    echo "Installed wm8960_asound.state"
else
    echo "Warning: wm8960_asound.state not found in script directory"
fi

echo ""
echo "Step 9/11: Installing systemd service script..."
# Copy service script to /usr/bin
if [ -f "$SCRIPT_DIR/wm8960-soundcard.sh" ]; then
    cp "$SCRIPT_DIR/wm8960-soundcard.sh" /usr/bin/wm8960-soundcard
    chmod +x /usr/bin/wm8960-soundcard
    echo "Installed wm8960-soundcard service script"
else
    echo "Error: wm8960-soundcard.sh not found in script directory"
    exit 1
fi

echo ""
echo "Step 10/11: Installing systemd service..."
# Copy systemd service file
if [ -f "$SCRIPT_DIR/wm8960-soundcard.service" ]; then
    cp "$SCRIPT_DIR/wm8960-soundcard.service" /etc/systemd/system/
    echo "Installed wm8960-soundcard.service"
else
    echo "Error: wm8960-soundcard.service not found in script directory"
    exit 1
fi

echo ""
echo "Step 11/11: Enabling and starting systemd service..."
systemctl daemon-reload
systemctl enable wm8960-soundcard.service
echo "Service enabled to start on boot"

echo ""
echo "==============================================="
echo "Installation Complete!"
echo "==============================================="
echo ""
echo "IMPORTANT: You must reboot your Raspberry Pi for changes to take effect."
echo ""
echo "After rebooting, verify the installation with these commands:"
echo ""
echo "1. Check service status:"
echo "   sudo systemctl status wm8960-soundcard.service"
echo ""
echo "2. Check I2C device detection:"
echo "   sudo i2cdetect -y 1"
echo ""
echo "3. Check kernel modules:"
echo "   lsmod | grep snd_soc"
echo ""
echo "4. List sound cards:"
echo "   cat /proc/asound/cards"
echo ""
echo "5. Check DKMS status:"
echo "   sudo dkms status"
echo ""
echo "6. Test audio playback:"
echo "   aplay -l"
echo "   speaker-test -t wav -c 2"
echo ""
echo "7. Review service logs:"
echo "   sudo cat /var/log/wm8960-soundcard.log"
echo ""
echo "For detailed troubleshooting, see the README.md file."
echo ""
echo "Reboot now? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "Rebooting..."
    reboot
else
    echo "Please reboot manually when ready: sudo reboot"
fi
