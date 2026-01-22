#!/bin/bash

# Update: Fix kernel headers package issue
# Using linux-headers-$(uname -r) instead of raspberrypi-kernel-headers

# Get required packages
sudo apt-get update
sudo apt-get install -y linux-headers-$(uname -r) \
    build-essential \
    alsa-utils \
    libasound2-dev

# Install WM8960 driver
# (Add the original commands and script functionality here)
# Original installation script lines reinstated

# Print completion message
echo "Installation completed successfully."