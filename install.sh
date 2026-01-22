#!/bin/bash

# Update and install dependencies
apt-get update
apt-get -y install git
apt-get -y install build-essential
apt-get -y install linux-headers-$(uname -r)

# Clone the repository
# ... (remaining script contents) ...
