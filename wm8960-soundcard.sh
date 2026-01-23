#!/bin/bash
# WM8960 Soundcard Service Script
# This script dynamically loads the WM8960 overlay after detecting the I2C codec
# It runs on boot via systemd service and ensures proper initialization order

set -x
exec 1>/var/log/wm8960-soundcard.log 2>&1

# Enable I2C
dtparam i2c_arm=on

# Load kernel modules
modprobe i2c-dev
sleep 5

# Detect WM8960 codec on I2C bus 1, address 0x1a
for loop in 1 2 3 4 5; do
  is_1a=$(i2cdetect -y 1 0x1a 0x1a | egrep '(1a|UU)' | awk '{print $2}')
  if [ "x${is_1a}" != "x" ]; then
    break
  fi
  sleep 2
done

# Check if codec was found
if [ "x${is_1a}" != "x" ]; then
  echo "WM8960 codec detected at I2C address 0x1a"
  
  echo "Loading wm8960-soundcard overlay..."
  # Load the WM8960 overlay dynamically (ONLY HERE - not in config.txt)
  # No need to disable /sound node - we use unique driver name "asoc-wm8960-soundcard"
  dtoverlay wm8960-soundcard
  sleep 1
  
  # Remove old ALSA config files
  rm -f /etc/asound.conf
  rm -f /var/lib/alsa/asound.state
  
  # Create symlinks to new config files
  echo "Creating wm8960-soundcard configuration symlinks..."
  ln -s /etc/wm8960-soundcard/asound.conf /etc/asound.conf
  echo "Created asound.conf symlink"
  ln -s /etc/wm8960-soundcard/wm8960_asound.state /var/lib/alsa/asound.state
  echo "Created asound.state symlink"
  
  # Restore ALSA state (suppress warnings about missing controls)
  echo "Restoring ALSA mixer state..."
  alsactl restore 2>/dev/null || echo "Note: Some ALSA controls may not be available yet"
  
  echo "WM8960 service initialization complete"
else
  echo "WARNING: WM8960 codec not detected at I2C address 0x1a"
  echo "Please verify:"
  echo "  1. WM8960 HAT is properly seated on GPIO pins"
  echo "  2. I2C is enabled (dtparam=i2c_arm=on in config.txt)"
  echo "  3. Hardware connections are secure"
  echo "The service will exit. Check hardware and restart: sudo systemctl restart wm8960-soundcard.service"
  exit 1
fi