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
  echo "install wm8960-soundcard"
  
  # Load the WM8960 overlay dynamically (ONLY HERE - not in config.txt)
dtoverlay wm8960-soundcard
  sleep 1
  
  # Remove old ALSA config files
  rm /etc/asound.conf
  rm /var/lib/alsa/asound.state
  
  # Create symlinks to new config files
  echo "create wm8960-soundcard configure file"
  ln -s /etc/wm8960-soundcard/asound.conf /etc/asound.conf
  echo "create wm8960-soundcard status file"
  ln -s /etc/wm8960-soundcard/wm8960_asound.state /var/lib/alsa/asound.state
  
  break
fi

# Restore ALSA state (suppress warnings about missing vc4hdmi state)
# The complete state file includes both vc4hdmi and wm8960soundcard
alsactl restore 2>/dev/null

echo "WM8960 service initialization complete"