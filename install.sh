#!/bin/bash

# Install required packages
apt-get update
apt-get -y install git
apt-get -y install build-essential

# Install Raspberry Pi Kernel Headers
#apt-get -y install raspberrypi-kernel-headers
apt-get -y install linux-headers-$(uname -r)

# Clone the WM8960 Driver
if [ ! -d "WM8960_AudioHAT_Drivers" ]; then
    git clone https://github.com/MJD19994/WM8960_AudioHAT_Drivers.git
fi

cd WM8960_AudioHAT_Drivers

# Build the driver
make

# Install the driver
make install

# Clean up
make clean

echo "Installation completed!"