#!/bin/bash

# WM8960 Audio HAT Installation Script
# This script properly configures the WM8960 codec with correct device ordering
# IMPORTANT: This script DOES NOT add dtoverlay to config.txt - the service loads it dynamically

set -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 1>&2
   exit 1
fi

is_Raspberry=$(cat /proc/device-tree/model | awk  '{print $1}')
if [ "x${is_Raspberry}" != "xRaspberry" ] ; then
  echo "Sorry, this driver only works on Raspberry Pi"
  exit 1
fi

echo "======================================"
echo "WM8960 Audio HAT Installation"
echo "======================================"

# Step 1: Update package lists
echo "Step 1: Updating package lists..."
apt update
apt-get -y install linux-headers-$(uname -r)
apt-get -y install dkms git i2c-tools libasound2-plugins

# Step 2: Get kernel info
echo "Step 2: Getting kernel information..."
uname_r=$(uname -r)
echo "Kernel version: $uname_r"

# Step 3: Install kernel modules
echo "Step 3: Installing WM8960 kernel modules via DKMS..."
marker="0.0.0"

# Function to install kernel modules
function install_module {
  src=$1
  mod=$2

  if [[ -d /var/lib/dkms/$mod/$ver/$marker ]]; then
    rmdir /var/lib/dkms/$mod/$ver/$marker
  fi

  if [[ -e /usr/src/$mod-$ver || -e /var/lib/dkms/$mod/$ver ]]; then
    echo "  Removing previous $mod installation..."
    dkms remove --force -m $mod -v $ver --all
    rm -rf /usr/src/$mod-$ver
  fi
  
echo "  Installing $mod..."
  mkdir -p /usr/src/$mod-$ver
  cp -a $src/* /usr/src/$mod-$ver/
  dkms add -m $mod -v $ver
  dkms build $uname_r -m $mod -v $ver && dkms install --force $uname_r -m $mod -v $ver
  echo "  ✓ $mod installed successfully"
}

install_module "./" "wm8960-soundcard"

# Step 4: Copy device tree blob
echo "Step 4: Installing device tree overlay..."
cp wm8960-soundcard.dtbo /boot/overlays/
echo "  ✓ Overlay installed to /boot/overlays/wm8960-soundcard.dtbo"

# Step 5: Configure kernel modules (NOT device tree overlays - those are loaded by service)
echo "Step 5: Configuring kernel modules in /etc/modules..."
grep -q "i2c-dev" /etc/modules || echo "i2c-dev" >> /etc/modules
grep -q "snd-soc-wm8960" /etc/modules || echo "snd-soc-wm8960" >> /etc/modules
grep -q "snd-soc-wm8960-soundcard" /etc/modules || echo "snd-soc-wm8960-soundcard" >> /etc/modules
echo "  ✓ Kernel modules configured"

# Step 6: Configure device tree overlays in config.txt
# CRITICAL: We do NOT add dtoverlay=wm8960-soundcard here - the service loads it dynamically
echo "Step 6: Configuring device tree parameters in /boot/firmware/config.txt..."
sed -i -e 's:#dtparam=i2c_arm=on:dtparam=i2c_arm=on:g' /boot/firmware/config.txt || true
grep -q "dtoverlay=i2s-mmap" /boot/firmware/config.txt || echo "dtoverlay=i2s-mmap" >> /boot/firmware/config.txt
grep -q "dtparam=i2s=on" /boot/firmware/config.txt || echo "dtparam=i2s=on" >> /boot/firmware/config.txt
echo "  ✓ Device tree parameters configured"
echo "  ✓ dtoverlay=wm8960-soundcard NOT added (will be loaded by service)"

# Step 7: Install ALSA configuration files
echo "Step 7: Installing ALSA configuration files..."
mkdir -p /etc/wm8960-soundcard
cp asound.conf /etc/wm8960-soundcard/
cp wm8960_asound.state /etc/wm8960-soundcard/
echo "  ✓ ALSA config files installed"

# Step 8: Install service script
echo "Step 8: Installing WM8960 service script..."
cp wm8960-soundcard /usr/bin/
chmod +x /usr/bin/wm8960-soundcard
echo "  ✓ Service script installed to /usr/bin/wm8960-soundcard"

# Step 9: Install systemd service
echo "Step 9: Installing systemd service..."
cp wm8960-soundcard.service /lib/systemd/system/
systemctl daemon-reload
systemctl enable wm8960-soundcard.service
echo "  ✓ Service installed and enabled"

echo ""
echo "======================================"
echo "Installation completed successfully!"
echo "======================================"
echo ""
echo "Next steps:"
echo "1. Reboot your Raspberry Pi: sudo reboot"
echo "2. After reboot, verify installation:"
echo "   aplay -l          # Check playback devices"
echo "   arecord -l        # Check recording devices"
echo "   arecord -D hw:1,0 -r 48000 -c 2 -f S16_LE -d 3 /tmp/test.wav"
echo "   aplay /tmp/test.wav"
echo ""
echo "For troubleshooting, see TROUBLESHOOTING.md"
echo "======================================"