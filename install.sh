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

echo "Step 1/13: Updating package lists..."
timeout 120 apt-get update || echo "Warning: apt-get update timed out or failed. Package installations may fail if repositories are not accessible."

echo ""
echo "Step 2/13: Installing kernel headers..."
apt-get install -y linux-headers-$(uname -r)

echo ""
echo "Step 3/13: Installing required packages..."
apt-get install -y dkms git i2c-tools libasound2-plugins

echo ""
echo "Step 3a/13: Configuring I2C interface in config.txt..."
# Detect boot partition location
if [ -f "/boot/firmware/config.txt" ]; then
    CONFIG_FILE="/boot/firmware/config.txt"
elif [ -f "/boot/config.txt" ]; then
    CONFIG_FILE="/boot/config.txt"
else
    echo "Error: config.txt not found in /boot/firmware or /boot"
    exit 1
fi

echo "Using config file: $CONFIG_FILE"

# Backup config.txt before making any changes
BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"
echo "Backed up config.txt to $BACKUP_FILE"
echo "Note: Backup files accumulate with each run. Old backups can be safely removed to save space."

# Check if dtparam=i2c_arm=on is already present (exclude commented lines)
if ! grep -qE "^[^#]*dtparam=i2c_arm=on" "$CONFIG_FILE"; then
    echo "Adding dtparam=i2c_arm=on to config.txt..."
    
    # Try to add it to [all] section if it exists
    if grep -qE "^[[:space:]]*\[all\]" "$CONFIG_FILE"; then
        # Insert after [all] section header (handles potential whitespace)
        if ! sed -i '/^[[:space:]]*\[all\]/a dtparam=i2c_arm=on' "$CONFIG_FILE"; then
            echo "ERROR: Failed to add dtparam=i2c_arm=on to config.txt"
            exit 1
        fi
        echo "Added dtparam=i2c_arm=on to [all] section"
    else
        # No [all] section, append to end of file
        echo "" >> "$CONFIG_FILE"
        echo "[all]" >> "$CONFIG_FILE"
        echo "dtparam=i2c_arm=on" >> "$CONFIG_FILE"
        echo "Added [all] section with dtparam=i2c_arm=on"
    fi
    
    # Verify dtparam was actually added to config.txt
    if ! grep -qE "^[^#]*dtparam=i2c_arm=on" "$CONFIG_FILE"; then
        echo "ERROR: Failed to verify dtparam=i2c_arm=on in config.txt"
        exit 1
    fi
else
    echo "dtparam=i2c_arm=on already present in config.txt"
fi

# Check for dtoverlay=i2s-mmap conflict and warn user
# This warns if user already has i2s-mmap from a previous install or custom setup
# The script will add i2s-mmap later if not present, but warns if it already exists
# in case the user is experiencing conflicts and needs to know about it
if grep -qE "^[^#]*dtoverlay=i2s-mmap" "$CONFIG_FILE"; then
    echo ""
    echo "=========================================="
    echo "WARNING: I2S-MMAP Overlay Already Present"
    echo "=========================================="
    echo "Your config.txt already contains 'dtoverlay=i2s-mmap'."
    echo ""
    echo "This is usually correct, but if you experience audio issues after"
    echo "installation (silent failures, unexpected behavior), this overlay"
    echo "may conflict with WM8960. You can comment it out:"
    echo "  # dtoverlay=i2s-mmap  # Commented out due to WM8960 conflict"
    echo ""
    echo "See README.md 'Required config.txt Settings' section for more details."
    echo "=========================================="
    echo ""
    if [ -t 0 ]; then
        read -p "Press Enter to continue with installation..."
    else
        echo "Non-interactive mode, continuing..."
    fi
fi

echo ""
echo "Step 4/13: Compiling and installing wm8960-soundcard kernel module via DKMS..."
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
echo "Step 5/13: Copying device tree overlay..."
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
echo "Step 6/13: Configuring kernel modules in /etc/modules..."
# Add i2c-dev to /etc/modules if not present
if ! grep -q "^i2c-dev" /etc/modules; then
    echo "i2c-dev" >> /etc/modules
    echo "Added i2c-dev to /etc/modules"
fi

echo ""
echo "Step 7/13: Configuring I2S interface in /boot/firmware/config.txt..."
# CONFIG_FILE already set in Step 3a

# Enable I2S-MMAP (required for proper I2S memory-mapped interface)
# Note: In rare cases, this may conflict with custom audio setups
# If you experience audio issues after installation, try commenting out dtoverlay=i2s-mmap in config.txt

# Remove old dtparam=i2s=on if present
if grep -qE "^[[:space:]]*dtparam=i2s=on" "$CONFIG_FILE"; then
    if ! sed -i 's/^[[:space:]]*dtparam=i2s=on/# dtparam=i2s=on  # Replaced by dtoverlay=i2s-mmap/' "$CONFIG_FILE"; then
        echo "ERROR: Failed to comment out dtparam=i2s=on in config.txt"
        exit 1
    fi
    echo "Replaced dtparam=i2s=on with dtoverlay=i2s-mmap"
fi

# Add dtoverlay=i2s-mmap if not present
if ! grep -qE "^[^#]*dtoverlay=i2s-mmap" "$CONFIG_FILE"; then
    # Try to add it to [all] section if it exists
    if grep -qE "^[[:space:]]*\[all\]" "$CONFIG_FILE"; then
        # Insert after dtparam=i2c_arm=on if it exists, otherwise after [all] section header
        if grep -qE "^[^#]*dtparam=i2c_arm=on" "$CONFIG_FILE"; then
            if ! sed -i '/^[^#]*dtparam=i2c_arm=on/a dtoverlay=i2s-mmap' "$CONFIG_FILE"; then
                echo "ERROR: Failed to add dtoverlay=i2s-mmap to config.txt"
                exit 1
            fi
        else
            if ! sed -i '/^[[:space:]]*\[all\]/a dtoverlay=i2s-mmap' "$CONFIG_FILE"; then
                echo "ERROR: Failed to add dtoverlay=i2s-mmap to config.txt"
                exit 1
            fi
        fi
        echo "Added dtoverlay=i2s-mmap to [all] section"
    else
        # No [all] section exists, should have been created earlier when adding dtparam=i2c_arm=on
        echo "dtoverlay=i2s-mmap" >> "$CONFIG_FILE"
        echo "Added dtoverlay=i2s-mmap to end of config.txt"
    fi
    echo "Enabled I2S-MMAP overlay in config.txt"
    echo ""
    echo "NOTE: If you experience audio issues (silent failures, unexpected behavior),"
    echo "      you may need to comment out dtoverlay=i2s-mmap in config.txt."
    echo "      See README.md 'Required config.txt Settings' section for details."
    echo ""
fi

# Add informational comment about dynamic loading benefits
# Dynamic loading allows for I2C detection and proper initialization timing
if ! grep -qF "# Note: wm8960-soundcard overlay loaded dynamically by service for proper I2C detection" "$CONFIG_FILE"; then
    echo "" >> "$CONFIG_FILE"
    echo "# Note: wm8960-soundcard overlay loaded dynamically by service for proper I2C detection" >> "$CONFIG_FILE"
fi

# Note: We do NOT add dtoverlay=wm8960-soundcard here - loaded dynamically by service
echo "Note: wm8960-soundcard overlay will be loaded dynamically by the systemd service"

echo ""
echo "Step 8/13: Installing ALSA configuration files..."
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
echo "Step 9/13: Installing systemd service script..."
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
echo "Step 10/13: Installing systemd service file..."
# Copy systemd service file
if [ -f "$SCRIPT_DIR/wm8960-soundcard.service" ]; then
    cp "$SCRIPT_DIR/wm8960-soundcard.service" /etc/systemd/system/
    echo "Installed wm8960-soundcard.service"
else
    echo "Error: wm8960-soundcard.service not found in script directory"
    exit 1
fi

echo ""
echo "Step 11/13: Installing ALSA auto-save components (disabled by default)..."
# Copy auto-save script to /usr/bin
if [ -f "$SCRIPT_DIR/wm8960-alsa-store" ]; then
    cp "$SCRIPT_DIR/wm8960-alsa-store" /usr/bin/wm8960-alsa-store
    chmod +x /usr/bin/wm8960-alsa-store
    echo "Installed wm8960-alsa-store script"
else
    echo "Warning: wm8960-alsa-store script not found in script directory"
fi

# Copy auto-save service file
if [ -f "$SCRIPT_DIR/wm8960-alsa-store.service" ]; then
    cp "$SCRIPT_DIR/wm8960-alsa-store.service" /etc/systemd/system/
    echo "Installed wm8960-alsa-store.service"
else
    echo "Warning: wm8960-alsa-store.service not found in script directory"
fi

# Copy auto-save timer file
if [ -f "$SCRIPT_DIR/wm8960-alsa-store.timer" ]; then
    cp "$SCRIPT_DIR/wm8960-alsa-store.timer" /etc/systemd/system/
    echo "Installed wm8960-alsa-store.timer"
else
    echo "Warning: wm8960-alsa-store.timer not found in script directory"
fi

echo ""
echo "Step 12/13: Enabling and starting systemd service..."
systemctl daemon-reload
systemctl enable wm8960-soundcard.service
echo "Service enabled to start on boot"

echo ""
echo "Step 13/13: Validating installation..."
# Verify critical files and configurations
validation_errors=0

# Check if DKMS module was installed
if dkms status | grep -q "wm8960-soundcard/1.0"; then
    echo "✓ DKMS module installed"
else
    echo "✗ DKMS module not found"
    validation_errors=$((validation_errors + 1))
fi

# Check if device tree overlay was copied
if [ -f "$BOOT_OVERLAYS/wm8960-soundcard.dtbo" ]; then
    echo "✓ Device tree overlay installed"
else
    echo "✗ Device tree overlay not found"
    validation_errors=$((validation_errors + 1))
fi

# Check if systemd service was installed
if [ -f "/etc/systemd/system/wm8960-soundcard.service" ]; then
    echo "✓ Systemd service installed"
else
    echo "✗ Systemd service not found"
    validation_errors=$((validation_errors + 1))
fi

# Check if config files were copied
if [ -f "/etc/wm8960-soundcard/asound.conf" ] && [ -f "/etc/wm8960-soundcard/wm8960_asound.state" ]; then
    echo "✓ ALSA configuration files installed"
else
    echo "✗ ALSA configuration files not found"
    validation_errors=$((validation_errors + 1))
fi

# Check if config.txt was modified correctly
if grep -qE "^[^#]*dtparam=i2c_arm=on" "$CONFIG_FILE"; then
    echo "✓ I2C enabled in config.txt"
else
    echo "✗ I2C not enabled in config.txt"
    validation_errors=$((validation_errors + 1))
fi

if [ $validation_errors -eq 0 ]; then
    echo ""
    echo "All validation checks passed!"
else
    echo ""
    echo "Warning: $validation_errors validation check(s) failed. Review errors above."
fi

echo ""
echo "==============================================="
echo "Installation Complete!"
echo "==============================================="
echo ""
echo "IMPORTANT: You must reboot your Raspberry Pi for changes to take effect."
echo ""
echo "==============================================="
echo "Audio Settings Management"
echo "==============================================="
echo ""
echo "By default, audio mixer settings are NOT automatically saved."
echo "After configuring your audio settings (volume, etc.), save them with:"
echo "   sudo alsactl store"
echo ""
echo "OPTIONAL: Enable automatic saving every 6 hours:"
echo "   sudo systemctl enable wm8960-alsa-store.timer"
echo "   sudo systemctl start wm8960-alsa-store.timer"
echo ""
echo "To check auto-save status:"
echo "   sudo systemctl status wm8960-alsa-store.timer"
echo ""
echo "See README.md 'Saving Audio Settings' section for more details."
echo ""
echo "==============================================="
echo "Post-Installation Verification"
echo "==============================================="
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
if [ -t 0 ]; then
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Rebooting..."
        reboot
    else
        echo "Please reboot manually when ready: sudo reboot"
    fi
else
    echo "Non-interactive mode detected. Please reboot manually when ready: sudo reboot"
fi
