#!/bin/bash

# Uninstall WM8960 Drivers
echo "Removing WM8960 drivers..."

# Make a backup of config.txt before making any changes
cp /boot/firmware/config.txt /boot/firmware/config.txt.bak

# Remove or comment out the lines related to WM8960
sed -i '/^#?dtparam=audio=on/d' /boot/firmware/config.txt
sed -i '/^#?dtoverlay=wm8960,/d' /boot/firmware/config.txt

echo "WM8960 drivers have been removed."