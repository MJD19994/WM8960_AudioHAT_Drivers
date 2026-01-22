#!/bin/bash

set -e

echo "==============================================="
echo "WM8960 Audio HAT Uninstallation Script"
echo "==============================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

echo "Step 1/9: Stopping and disabling systemd service..."
systemctl stop wm8960-soundcard.service 2>/dev/null || echo "Service not running"
systemctl disable wm8960-soundcard.service 2>/dev/null || echo "Service not enabled"

echo ""
echo "Step 2/9: Removing systemd service files..."
rm -f /etc/systemd/system/wm8960-soundcard.service
rm -f /usr/bin/wm8960-soundcard
systemctl daemon-reload
echo "Service files removed"

echo ""
echo "Step 3/9: Removing ALSA configuration symlinks..."
rm -f /etc/asound.conf
rm -f /var/lib/alsa/asound.state
echo "Symlinks removed"

echo ""
echo "Step 4/9: Removing ALSA configuration directory..."
rm -rf /etc/wm8960-soundcard
echo "Configuration directory removed"

echo ""
echo "Step 5/9: Removing service log file..."
rm -f /var/log/wm8960-soundcard.log
echo "Log file removed"

echo ""
echo "Step 6/9: Removing DKMS kernel module..."
if dkms status | grep -q "wm8960-soundcard"; then
    dkms remove wm8960-soundcard/1.0 --all
    # Verify removal was successful
    if ! dkms status | grep -q "wm8960-soundcard"; then
        echo "All DKMS modules successfully removed"
    else
        echo "Warning: Some DKMS modules may still be installed"
    fi
else
    echo "DKMS module not found, skipping..."
fi

echo ""
echo "Step 7/9: Removing DKMS source files..."
rm -rf /usr/src/wm8960-soundcard-1.0
echo "DKMS source files removed"

echo ""
echo "Step 8/9: Removing device tree overlay..."
rm -f /boot/overlays/wm8960-soundcard.dtbo
echo "Device tree overlay removed (if present)"

echo ""
echo "Step 9/9: Cleaning up config.txt..."
CONFIG_FILE="/boot/firmware/config.txt"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="/boot/config.txt"
fi

# Make a backup of config.txt before making any changes
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Remove WM8960-related overlay entries (if any were manually added)
sed -i '/^dtoverlay=wm8960-soundcard/d' "$CONFIG_FILE"
# Remove only wm8960-soundcard specific comments
sed -i '/^#.*wm8960-soundcard/d' "$CONFIG_FILE"

echo "Config.txt cleaned (backup created)"

echo ""
echo "==============================================="
echo "Uninstallation Complete!"
echo "==============================================="
echo ""
echo "The following items were NOT removed (manual cleanup if desired):"
echo "  - I2C and I2S enabling in config.txt (dtparam=i2c_arm=on, dtparam=i2s=on)"
echo "  - i2c-dev in /etc/modules"
echo "  - Installed packages (dkms, i2c-tools, libasound2-plugins)"
echo "  - Kernel headers"
echo ""
echo "To remove these manually:"
echo "  1. Edit $CONFIG_FILE and remove dtparam lines if not needed"
echo "  2. Edit /etc/modules and remove i2c-dev if not needed"
echo "  3. apt-get remove dkms i2c-tools (if not needed by other software)"
echo ""
echo "IMPORTANT: Reboot your Raspberry Pi for changes to take effect."
echo ""
echo "Reboot now? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "Rebooting..."
    reboot
else
    echo "Please reboot manually when ready: sudo reboot"
fi