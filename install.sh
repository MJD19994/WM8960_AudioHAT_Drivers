#!/bin/bash
# Installation script for WM8960 Audio HAT Drivers

# Remove static dtoverlay load
sudo dtoverlay -r wm8960_soundcard

# Continue with installation steps...
echo "Installation completed!"