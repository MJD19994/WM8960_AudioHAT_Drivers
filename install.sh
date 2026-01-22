#!/bin/bash

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Update package lists
apt-get update

# Install required packages
apt-get -y install linux-headers-$(uname -r)
apt-get -y install build-essential

# Clone the repository
if [ ! -d "WM8960_AudioHAT_Drivers" ]; then
    git clone https://github.com/MJD19994/WM8960_AudioHAT_Drivers.git
fi

# Build the drivers
cd WM8960_AudioHAT_Drivers
make

# Install the drivers
make install

echo "Installation complete!"