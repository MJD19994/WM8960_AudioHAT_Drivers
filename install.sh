#!/bin/bash

# Install script for WM8960 AudioHAT Drivers

# Update package list
apt-get update

# Install necessary packages
apt-get -y install linux-headers-$(uname -r)
# other installation commands...
