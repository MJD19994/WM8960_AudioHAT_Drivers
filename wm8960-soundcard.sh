#!/bin/bash
# WM8960 Soundcard Service Script
# This script dynamically loads the WM8960 overlay after detecting the I2C codec
# It runs on boot via systemd service and ensures proper initialization order

# Enable debug mode if DEBUG environment variable is set
if [ "${DEBUG}" = "1" ]; then
  set -x
fi

# Redirect output to log file
exec 1>/var/log/wm8960-soundcard.log 2>&1

# Function to log messages with timestamp
log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to log error and exit
log_error_exit() {
  log_message "ERROR: $1"
  exit "${2:-1}"
}

log_message "Starting WM8960 soundcard initialization..."

# Verify I2C is enabled (should be done via config.txt by install script)
log_message "Verifying I2C interface is available..."
if ! i2cdetect -y 1 >/dev/null 2>&1; then
  log_error_exit "I2C bus not available. Please add 'dtparam=i2c_arm=on' to config.txt [all] section (usually /boot/firmware/config.txt or /boot/config.txt) and reboot." 2
fi
log_message "I2C interface verified"

# Load kernel modules
log_message "Loading i2c-dev kernel module..."
if ! modprobe i2c-dev; then
  log_error_exit "Failed to load i2c-dev kernel module" 2
fi
log_message "i2c-dev module loaded successfully"
sleep 5

# Detect WM8960 codec on I2C bus 1, address 0x1a
log_message "Detecting WM8960 codec on I2C bus 1 at address 0x1a..."
for loop in 1 2 3 4 5; do
  log_message "Detection attempt $loop/5..."
  is_1a=$(i2cdetect -y 1 0x1a 0x1a 2>/dev/null | egrep '(1a|UU)' | awk '{print $2}')
  if [ "x${is_1a}" != "x" ]; then
    log_message "WM8960 codec detected on attempt $loop"
    break
  fi
  if [ "$loop" -lt 5 ]; then
    log_message "Codec not detected, waiting before retry..."
    sleep 2
  fi
done

# Check if codec was found
if [ "x${is_1a}" != "x" ]; then
  log_message "SUCCESS: WM8960 codec detected at I2C address 0x1a (value: ${is_1a})"
  
  # Check if overlay is already loaded before attempting to load
  # dtoverlay -l lists overlays in format: "N_overlayname" where N is the overlay number
  if dtoverlay -l | grep -qE "[0-9]+_wm8960-soundcard"; then
    log_message "WM8960 overlay already loaded, skipping overlay load"
  else
    log_message "Loading wm8960-soundcard device tree overlay..."
    # Load the WM8960 overlay dynamically (ONLY HERE - not in config.txt)
    # No need to disable /sound node - we use unique driver name "asoc-wm8960-soundcard"
    if ! dtoverlay wm8960-soundcard; then
      log_error_exit "Failed to load wm8960-soundcard overlay" 3
    fi
    log_message "Device tree overlay loaded successfully"
  fi
  sleep 1
  
  # Safer ALSA config management - backup before removing
  log_message "Managing ALSA configuration files..."
  if [ -f /etc/asound.conf ] && [ ! -L /etc/asound.conf ]; then
    log_message "Backing up existing /etc/asound.conf"
    if ! cp /etc/asound.conf /etc/asound.conf.backup.$(date +%Y%m%d_%H%M%S); then
      log_message "WARNING: Failed to create backup of /etc/asound.conf (continuing anyway)"
    fi
  fi
  if [ -f /var/lib/alsa/asound.state ] && [ ! -L /var/lib/alsa/asound.state ]; then
    log_message "Backing up existing /var/lib/alsa/asound.state"
    if ! cp /var/lib/alsa/asound.state /var/lib/alsa/asound.state.backup.$(date +%Y%m%d_%H%M%S); then
      log_message "WARNING: Failed to create backup of /var/lib/alsa/asound.state (continuing anyway)"
    fi
  fi
  
  # Remove old ALSA config files (use -f to avoid errors if files don't exist)
  rm -f /etc/asound.conf
  rm -f /var/lib/alsa/asound.state
  log_message "Removed old ALSA configuration files"
  
  # Create symlinks to new config files (use -sf to safely overwrite)
  log_message "Creating wm8960-soundcard configuration symlinks..."
  
  # Verify target files exist before creating symlinks
  if [ ! -f /etc/wm8960-soundcard/asound.conf ]; then
    log_error_exit "Source file /etc/wm8960-soundcard/asound.conf not found" 4
  fi
  if [ ! -f /etc/wm8960-soundcard/wm8960_asound.state ]; then
    log_error_exit "Source file /etc/wm8960-soundcard/wm8960_asound.state not found" 4
  fi
  
  # Create symlinks with force flag to safely overwrite existing ones
  if ! ln -sf /etc/wm8960-soundcard/asound.conf /etc/asound.conf; then
    log_error_exit "Failed to create asound.conf symlink" 5
  fi
  log_message "Created /etc/asound.conf symlink"
  
  if ! ln -sf /etc/wm8960-soundcard/wm8960_asound.state /var/lib/alsa/asound.state; then
    log_error_exit "Failed to create asound.state symlink" 5
  fi
  log_message "Created /var/lib/alsa/asound.state symlink"
  
  # Restore ALSA state (suppress warnings about missing controls)
  log_message "Restoring ALSA mixer state..."
  if alsactl restore 2>/dev/null; then
    log_message "ALSA mixer state restored successfully"
  else
    log_message "NOTE: Some ALSA controls may not be available yet (this is normal)"
  fi
  
  # Health check: Verify audio system is working
  log_message "Performing health checks..."
  
  # Check 1: Verify WM8960 kernel modules are loaded
  if lsmod | grep -q "snd_soc_wm8960"; then
    log_message "✓ Health check passed: WM8960 kernel module loaded"
  else
    log_message "⚠ WARNING: WM8960 kernel module not detected in lsmod"
  fi
  
  # Check 2: Verify ALSA can see the sound card
  if cat /proc/asound/cards 2>/dev/null | grep -q "wm8960"; then
    log_message "✓ Health check passed: WM8960 sound card visible to ALSA"
  else
    log_message "⚠ WARNING: WM8960 sound card not visible in /proc/asound/cards"
  fi
  
  # Check 3: Verify playback devices are available
  if aplay -l 2>/dev/null | grep -q "wm8960"; then
    log_message "✓ Health check passed: WM8960 playback devices available"
  else
    log_message "⚠ WARNING: WM8960 playback devices not found"
  fi
  
  # Log kernel module version information if debug mode is enabled
  if [ "${DEBUG}" = "1" ]; then
    log_message "Debug: Kernel module information:"
    modinfo snd_soc_wm8960_soundcard 2>/dev/null | head -10 || log_message "Debug: Module info not available"
  fi
  
  log_message "WM8960 service initialization complete successfully"
else
  log_message "FAILURE: WM8960 codec not detected at I2C address 0x1a after 5 attempts"
  log_message "This could indicate:"
  log_message "  1. I2C bus not ready yet (less likely after 5 attempts with delays)"
  log_message "  2. WM8960 HAT not properly seated on GPIO pins"
  log_message "  3. Hardware not powered or faulty"
  log_message "  4. I2C interface not enabled in boot configuration"
  log_message ""
  log_message "Troubleshooting steps:"
  log_message "  1. Verify WM8960 HAT is properly connected"
  log_message "  2. Check that I2C is enabled: dtparam=i2c_arm=on in config.txt"
  log_message "  3. Verify hardware connections and power"
  log_message "  4. Check dmesg for I2C errors: dmesg | grep i2c"
  log_message "  5. Retry service: sudo systemctl restart wm8960-soundcard.service"
  log_message ""
  log_message "The service will exit with error code 1"
  exit 1
fi