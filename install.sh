#!/bin/bash

# Update package list
apt-get update

# Install dependencies
apt-get -y install python3 python3-pip git

# Install Linux kernel headers for the current kernel
apt-get -y install linux-headers-$(uname -r)

# Clone the repository
if [ ! -d "WM8960_AudioHAT_Drivers" ]; then
    git clone https://github.com/MJD19994/WM8960_AudioHAT_Drivers.git
fi

# Change to directory
cd WM8960_AudioHAT_Drivers

# Install drivers
pip3 install .

# Clean up
apt-get -y clean
