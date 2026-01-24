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

echo "Step 1/10: Stopping and disabling systemd service..."
systemctl stop wm8960-soundcard.service 2>/dev/null || echo "Service not running"
systemctl disable wm8960-soundcard.service 2>/dev/null || echo "Service not enabled"

echo ""
echo "Step 2/10: Stopping and disabling ALSA auto-save timer..."
systemctl stop wm8960-alsa-store.timer 2>/dev/null || echo "Timer not running"
systemctl disable wm8960-alsa-store.timer 2>/dev/null || echo "Timer not enabled"
systemctl stop wm8960-alsa-store.service 2>/dev/null || echo "Auto-save service not running"

echo ""
echo "Step 3/10: Removing systemd service files..."
rm -f /etc/systemd/system/wm8960-soundcard.service
rm -f /usr/bin/wm8960-soundcard
rm -f /etc/systemd/system/wm8960-alsa-store.service
rm -f /etc/systemd/system/wm8960-alsa-store.timer
rm -f /usr/bin/wm8960-alsa-store
systemctl daemon-reload
echo "Service files removed"

echo ""
echo "Step 4/10: Removing ALSA configuration symlink and backups..."
rm -f /etc/asound.conf
rm -f /var/lib/alsa/asound.state.backup.*
echo "ALSA configuration symlink and backups removed"

echo ""
echo "Step 5/10: Removing ALSA configuration directory..."
rm -rf /etc/wm8960-soundcard
echo "Configuration directory removed"

echo ""
echo "Step 6/10: Removing service log file..."
rm -f /var/log/wm8960-soundcard.log
echo "Log file removed"

echo ""
echo "Step 7/10: Removing DKMS kernel module..."
if dkms status | grep -q "wm8960-soundcard"; then
    dkms remove wm8960-soundcard/1.0 --all
    # Verify removal was successful
    if ! dkms status | grep -q "wm8960-soundcard"; then
        echo "DKMS package successfully removed"
    else
        echo "Warning: DKMS package may still be partially installed"
    fi
else
    echo "DKMS module not found, skipping..."
fi

echo ""
echo "Step 8/10: Removing DKMS source files..."
rm -rf /usr/src/wm8960-soundcard-1.0
echo "DKMS source files removed"

echo ""
echo "Step 9/10: Removing device tree overlay..."
rm -f /boot/overlays/wm8960-soundcard.dtbo
rm -f /boot/firmware/overlays/wm8960-soundcard.dtbo
echo "Device tree overlay removed (if present)"

echo ""
echo "Step 10/10: Cleaning up config.txt..."
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
# Remove dtparam=i2c_arm=on added by install script
sed -i '/^dtparam=i2c_arm=on/d' "$CONFIG_FILE"
# Remove dtoverlay=i2s-mmap added by install script
sed -i '/^dtoverlay=i2s-mmap/d' "$CONFIG_FILE"

echo "Config.txt cleaned (backup created)"

echo ""
echo "==============================================="
echo "Uninstallation Complete!"
echo "==============================================="
echo ""
echo "The following items were removed:"
echo "  - dtparam=i2c_arm=on (added by install script)"
echo "  - dtoverlay=i2s-mmap (added by install script)"
echo "  - WM8960-related comments"
echo ""
echo "The following items were NOT removed (manual cleanup if desired):"
echo "  - i2c-dev in /etc/modules"
echo "  - Installed packages (dkms, i2c-tools, libasound2-plugins)"
echo "  - Kernel headers"
echo ""
echo "To remove these manually:"
echo "  1. Edit /etc/modules and remove i2c-dev if not needed"
echo "  2. apt-get remove dkms i2c-tools (if not needed by other software)"
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