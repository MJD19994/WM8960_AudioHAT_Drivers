#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# WM8960 Soundcard Service Script
# This script dynamically loads the WM8960 overlay after detecting the I2C codec
# It runs on boot via systemd service and ensures proper initialization order

# Ensure sbin directories are in PATH (systemd services may not include them)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# Enable debug mode if DEBUG environment variable is set
if [ "${DEBUG}" = "1" ]; then
  set -x
fi

# Redirect output to log file (append to preserve previous boot logs)
exec 1>>/var/log/wm8960-soundcard.log 2>&1

# Function to log messages with timestamp
log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to log error and exit
log_error_exit() {
  log_message "ERROR: $1"
  exit "${2:-1}"
}

WM8960_VERSION="unknown"
if [ -f /etc/wm8960-soundcard/version ]; then
  WM8960_VERSION="$(tr -d '[:space:]' < /etc/wm8960-soundcard/version)"
fi
log_message "Starting WM8960 soundcard initialization (v${WM8960_VERSION})..."

# --- DKMS Auto-Rebuild Check ---
# On Raspberry Pi OS, kernel updates often install the image before the headers.
# The DKMS postinst hook fires when the image is installed, but skips the build
# because headers aren't available yet. When headers install seconds later, no
# hook retriggers DKMS. This leaves the custom WM8960 driver unbuilt for the new
# kernel, causing a silent fallback to the mainline driver which fails with
# "No MCLK configured". This boot-time check catches that case.
ensure_dkms_module() {
  local running_kernel
  running_kernel="$(uname -r)"
  local dkms_module="wm8960-soundcard"
  local dkms_version="1.0"

  # Skip if DKMS is not installed (user may be using mainline driver intentionally)
  if ! command -v dkms >/dev/null 2>&1; then
    log_message "DKMS not installed, skipping auto-rebuild check"
    return 0
  fi

  # Skip if DKMS source is not registered
  if ! dkms status "$dkms_module/$dkms_version" 2>/dev/null | grep -q "$dkms_module"; then
    log_message "DKMS module $dkms_module not registered, skipping auto-rebuild check"
    return 0
  fi

  # Check if module is already built+installed for the running kernel
  if dkms status "$dkms_module/$dkms_version" -k "$running_kernel" 2>/dev/null | grep -q "installed"; then
    log_message "DKMS module $dkms_module/$dkms_version is installed for kernel $running_kernel"
    return 0
  fi

  # Module is NOT installed for running kernel - attempt rebuild
  log_message "WARNING: DKMS module $dkms_module/$dkms_version is NOT installed for kernel $running_kernel"
  log_message "This typically happens after a kernel update. Attempting auto-rebuild..."

  # Check if kernel headers are available
  if [ ! -d "/lib/modules/$running_kernel/build/include" ]; then
    log_message "ERROR: Kernel headers not found for $running_kernel"
    log_message "Install them with: sudo apt-get install linux-headers-$running_kernel"
    log_message "Then rebuild with: sudo dkms install $dkms_module/$dkms_version -k $running_kernel"
    return 1
  fi

  # Check if module is already built (but not installed) - skip build, go straight to install
  if dkms status "$dkms_module/$dkms_version" -k "$running_kernel" 2>/dev/null | grep -q "built"; then
    log_message "DKMS module already built for kernel $running_kernel, skipping to install..."
  else
    # Attempt build
    log_message "Building DKMS module for kernel $running_kernel..."
    local build_output build_status
    build_output=$(dkms build "$dkms_module/$dkms_version" -k "$running_kernel" 2>&1)
    build_status=$?
    echo "$build_output" | while IFS= read -r line; do log_message "  dkms build: $line"; done
    if [ "$build_status" -eq 0 ]; then
      log_message "DKMS build succeeded"
    else
      log_message "ERROR: DKMS build failed for kernel $running_kernel"
      log_message "Check build log: /var/lib/dkms/$dkms_module/$dkms_version/build/make.log"
      return 1
    fi
  fi

  log_message "Installing DKMS module for kernel $running_kernel..."
  local install_output install_status
  install_output=$(dkms install "$dkms_module/$dkms_version" -k "$running_kernel" 2>&1)
  install_status=$?
  echo "$install_output" | while IFS= read -r line; do log_message "  dkms install: $line"; done
  if [ "$install_status" -eq 0 ]; then
    log_message "DKMS auto-rebuild completed successfully for kernel $running_kernel"
  else
    log_message "ERROR: DKMS install failed for kernel $running_kernel"
    return 1
  fi
}

ensure_dkms_module || log_message "WARNING: DKMS auto-rebuild failed - audio may not work (see errors above)"

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
  is_1a=$(i2cdetect -y 1 0x1a 0x1a 2>/dev/null | grep -oE '(1a|UU)')
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
    if ! cp /etc/asound.conf "/etc/asound.conf.backup.$(date +%Y%m%d_%H%M%S)"; then
      log_message "WARNING: Failed to create backup of /etc/asound.conf (continuing anyway)"
    fi
  fi
  if [ -f /var/lib/alsa/asound.state ] && [ ! -L /var/lib/alsa/asound.state ]; then
    log_message "Backing up existing /var/lib/alsa/asound.state"
    if ! cp /var/lib/alsa/asound.state "/var/lib/alsa/asound.state.backup.$(date +%Y%m%d_%H%M%S)"; then
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
  
  # Ensure /var/lib/alsa directory exists before creating symlink
  mkdir -p /var/lib/alsa
  if ! ln -sf /etc/wm8960-soundcard/wm8960_asound.state /var/lib/alsa/asound.state; then
    log_error_exit "Failed to create asound.state symlink" 5
  fi
  log_message "Created /var/lib/alsa/asound.state symlink"
  
  # Restore ALSA state (suppress warnings about missing controls)
  log_message "Restoring ALSA mixer state..."
  if [ -f /var/lib/alsa/asound.state ]; then
    if alsactl restore 2>/dev/null; then
      log_message "ALSA mixer state restored successfully"
    else
      log_message "NOTE: Some ALSA controls may not be available yet (this is normal)"
    fi
  else
    log_message "No saved ALSA state (first boot?)"
  fi
  
  # Clean up old backup files at boot (keep last 10 of each type)
  log_message "Cleaning up old ALSA backup files..."

  cleanup_old_backups() {
    local dir="$1" pattern="$2" keep="$3"
    local count
    count=$(find "$dir" -name "$pattern" 2>/dev/null | wc -l)
    count=${count:-0}
    if [ "$count" -gt "$keep" ]; then
      find "$dir" -name "$pattern" -type f 2>/dev/null | while IFS= read -r file; do
        mtime=$(stat -c '%Y' "$file" 2>/dev/null || stat -f '%m' "$file" 2>/dev/null)
        echo "$mtime|$file"
      done | sort -t'|' -k1,1n | cut -d'|' -f2- | head -n $((count - keep)) | while IFS= read -r file; do
        rm -f "$file" 2>/dev/null && log_message "Deleted old backup: $(basename "$file")"
      done
      log_message "Cleanup: kept last $keep of $pattern in $dir"
    fi
  }

  cleanup_old_backups "/var/lib/alsa" "asound.state.backup.*" 10
  cleanup_old_backups "/etc" "asound.conf.backup.*" 10
  log_message "Boot-time backup cleanup complete"
  
  # Health check: Verify audio system is working
  log_message "Performing health checks..."
  
  # Check 1: Verify WM8960 kernel modules are loaded
  if lsmod | grep -q "^snd_soc_wm8960 "; then
    log_message "[PASS] Health check: WM8960 kernel module loaded"
  else
    log_message "[WARN] WARNING: WM8960 kernel module not detected in lsmod"
  fi
  
  # Check 2: Verify ALSA can see the sound card
  if grep -q "wm8960" /proc/asound/cards 2>/dev/null; then
    log_message "[PASS] Health check: WM8960 sound card visible to ALSA"
  else
    log_message "[WARN] WARNING: WM8960 sound card not visible in /proc/asound/cards"
  fi
  
  # Check 3: Verify playback devices are available
  if aplay -l 2>/dev/null | grep -q "wm8960"; then
    log_message "[PASS] Health check: WM8960 playback devices available"
  else
    log_message "[WARN] WARNING: WM8960 playback devices not found"
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