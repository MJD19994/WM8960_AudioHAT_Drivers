#!/bin/bash
# SPDX-License-Identifier: MIT

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

echo "Step 1/11: Stopping and disabling systemd service..."
systemctl stop wm8960-soundcard.service 2>/dev/null || echo "Service not running"
systemctl disable wm8960-soundcard.service 2>/dev/null || echo "Service not enabled"

echo ""
echo "Step 2/11: Stopping and disabling ALSA auto-save timer..."
systemctl stop wm8960-alsa-store.timer 2>/dev/null || echo "Timer not running"
systemctl disable wm8960-alsa-store.timer 2>/dev/null || echo "Timer not enabled"
systemctl stop wm8960-alsa-store.service 2>/dev/null || echo "Auto-save service not running"

echo ""
echo "Step 3/11: Removing systemd service files..."
rm -f /etc/systemd/system/wm8960-soundcard.service
rm -f /usr/bin/wm8960-soundcard
rm -f /etc/systemd/system/wm8960-alsa-store.service
rm -f /etc/systemd/system/wm8960-alsa-store.timer
rm -f /usr/bin/wm8960-alsa-store
rm -f /usr/bin/wm8960-volume
rm -f /usr/bin/wm8960-diag
systemctl daemon-reload
echo "Service files and utilities removed"

echo ""
echo "Step 4/11: Removing ALSA WM8960 links and restoring previous config if available..."
# Only remove symlinks if they point to our config
if [ -L /etc/asound.conf ]; then
    if [ "$(readlink -f /etc/asound.conf)" = "/etc/wm8960-soundcard/asound.conf" ]; then
        rm -f /etc/asound.conf
        echo "Removed WM8960 ALSA config symlink"
    else
        echo "Skipping /etc/asound.conf (not a WM8960 symlink)"
    fi
elif [ -f /etc/asound.conf ]; then
    echo "Skipping /etc/asound.conf (regular file, not created by installer)"
fi

if [ -L /var/lib/alsa/asound.state ]; then
    if [ "$(readlink -f /var/lib/alsa/asound.state)" = "/etc/wm8960-soundcard/wm8960_asound.state" ]; then
        rm -f /var/lib/alsa/asound.state
        echo "Removed WM8960 ALSA state symlink"
    else
        echo "Skipping /var/lib/alsa/asound.state (not a WM8960 symlink)"
    fi
fi

# Restore previous ALSA config from backup if available
latest_asound_backup="$(find /etc -maxdepth 1 -name 'asound.conf.backup.*' -type f -printf '%T@|%p\n' 2>/dev/null | sort -t'|' -k1,1rn | head -n1 | cut -d'|' -f2-)"
if [ -n "$latest_asound_backup" ] && [ ! -f /etc/asound.conf ]; then
    cp "$latest_asound_backup" /etc/asound.conf
    echo "Restored /etc/asound.conf from $latest_asound_backup"
else
    echo "No previous /etc/asound.conf backup to restore"
fi

latest_state_backup="$(find /var/lib/alsa -maxdepth 1 -name 'asound.state.backup.*' -type f -printf '%T@|%p\n' 2>/dev/null | sort -t'|' -k1,1rn | head -n1 | cut -d'|' -f2-)"
if [ -n "$latest_state_backup" ] && [ ! -f /var/lib/alsa/asound.state ]; then
    cp "$latest_state_backup" /var/lib/alsa/asound.state
    echo "Restored /var/lib/alsa/asound.state from $latest_state_backup"
else
    echo "No previous ALSA state backup to restore"
fi

rm -f /etc/asound.conf.backup.*
rm -f /var/lib/alsa/asound.state.backup.*
echo "ALSA backup cleanup complete"

echo ""
echo "Step 5/11: Removing PipeWire and PulseAudio configurations..."
if [ -f "/etc/wireplumber/wireplumber.conf.d/40-wm8960-default.conf" ]; then
    rm -f /etc/wireplumber/wireplumber.conf.d/40-wm8960-default.conf
    echo "Removed WirePlumber configuration"
else
    echo "No WirePlumber configuration found (skipping)"
fi
if [ -f "/etc/pulse/default.pa.d/wm8960-default.pa" ]; then
    rm -f /etc/pulse/default.pa.d/wm8960-default.pa
    echo "Removed PulseAudio configuration"
else
    echo "No PulseAudio configuration found (skipping)"
fi

echo ""
echo "Step 6/11: Removing ALSA configuration directory..."
rm -rf /etc/wm8960-soundcard
echo "Configuration directory removed"

echo ""
echo "Step 7/11: Removing service log file..."
rm -f /var/log/wm8960-soundcard.log
rm -f /etc/logrotate.d/wm8960-soundcard
echo "Log file and logrotate config removed"

echo ""
echo "Step 8/11: Removing DKMS kernel module..."
dkms_still_registered=0
if ! command -v dkms >/dev/null 2>&1; then
    echo "DKMS command not found, skipping..."
else
    # Query DKMS state separately from the grep so a failure of dkms itself
    # (e.g., broken kernel build env) doesn't silently fall through as
    # "module not registered" — which would then delete the source tree.
    dkms_status_rc=0
    dkms_status_before="$(dkms status 2>&1)" || dkms_status_rc=$?
    if [ "$dkms_status_rc" -ne 0 ]; then
        dkms_still_registered=1
        echo "Warning: could not query DKMS status (dkms status exited $dkms_status_rc); keeping source files"
    elif printf '%s\n' "$dkms_status_before" | grep -q "wm8960-soundcard"; then
        dkms remove wm8960-soundcard/1.0 --all || echo "Warning: DKMS removal returned an error (continuing uninstall)"
        # Verify removal succeeded — same error-separation pattern.
        dkms_status_after_rc=0
        dkms_status_after="$(dkms status 2>&1)" || dkms_status_after_rc=$?
        if [ "$dkms_status_after_rc" -ne 0 ]; then
            dkms_still_registered=1
            echo "Warning: could not verify DKMS removal (dkms status exited $dkms_status_after_rc); keeping source files"
        elif printf '%s\n' "$dkms_status_after" | grep -q "wm8960-soundcard"; then
            dkms_still_registered=1
            echo "Warning: DKMS package may still be partially installed"
        else
            echo "DKMS package successfully removed"
        fi
    else
        echo "DKMS module not found, skipping..."
    fi
fi

echo ""
echo "Step 9/11: Removing DKMS source files..."
if [ "$dkms_still_registered" -eq 1 ]; then
    echo "Skipping DKMS source removal because DKMS package is still registered"
else
    rm -rf /usr/src/wm8960-soundcard-1.0
    echo "DKMS source files removed"
fi

echo ""
echo "Step 10/11: Removing device tree overlay..."
rm -f /boot/overlays/wm8960-soundcard.dtbo
rm -f /boot/firmware/overlays/wm8960-soundcard.dtbo
echo "Device tree overlay removed (if present)"

echo ""
echo "Step 11/11: Cleaning up config.txt..."
CONFIG_FILE="/boot/firmware/config.txt"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="/boot/config.txt"
fi

if [ -f "$CONFIG_FILE" ]; then
    # Make a backup of config.txt before making any changes
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

    # Remove WM8960-related overlay entries (if any were manually added by users).
    # Allow leading whitespace — some users indent lines inside [section] blocks.
    sed -i '/^[[:space:]]*dtoverlay=wm8960-soundcard/d' "$CONFIG_FILE"
    # Remove installer-managed lines (tagged with # wm8960-managed).
    # This includes dtparam=i2c_arm=on, dtoverlay=i2s-mmap, and our informational
    # comment — all tagged so we only remove what we added. User-authored comments
    # mentioning wm8960-soundcard are preserved.
    sed -i '/# wm8960-managed/d' "$CONFIG_FILE"

    echo "Config.txt cleaned (backup created)"
else
    echo "Warning: config.txt not found, skipping config cleanup"
fi

echo ""
echo "==============================================="
echo "Uninstallation Complete!"
echo "==============================================="
echo ""
echo "The following items were removed:"
echo "  - Lines tagged with '# wm8960-managed' in config.txt"
echo "  - WM8960-related overlay and comment lines"
echo ""
echo "The following items were NOT removed (manual cleanup if desired):"
echo "  - i2c-dev in /etc/modules"
echo "  - Installed packages (dkms, i2c-tools)"
echo "  - alsa-utils and libasound2-plugins are SHARED with most audio stacks"
echo "    (PulseAudio, PipeWire, Bluetooth audio) — leave installed unless you're sure"
echo "  - Kernel headers"
echo ""
echo "To remove these manually:"
echo "  1. Edit /etc/modules and remove i2c-dev if not needed"
echo "  2. apt-get remove dkms i2c-tools     # safe on most Pi setups"
echo "     apt-get remove alsa-utils libasound2-plugins   # ONLY if no other"
echo "                                                      audio software uses them"
echo ""
echo "IMPORTANT: Reboot your Raspberry Pi for changes to take effect."
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