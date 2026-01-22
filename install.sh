#!/bin/bash

# Update package name for kernel headers in Trixie
KERNEL_HEADERS_PKG="linux-headers-$(uname -r)"

# Function to handle errors
handle_error() {
    echo "Error: $1"
    exit 1
}

# Install kernel headers
if ! apt-get install -y $KERNEL_HEADERS_PKG; then
    handle_error "Failed to install kernel headers package: $KERNEL_HEADERS_PKG"
fi

# Add other installation steps here
