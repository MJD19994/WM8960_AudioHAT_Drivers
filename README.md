# WM8960 AudioHAT Drivers

## Overview
This repository contains drivers and configuration for the WM8960 Audio HAT for Raspberry Pi. The WM8960 is a low power stereo codec featuring Class D speaker drivers to reduce external component count and provide high quality audio output.

### Key Features
- High-quality stereo audio playback and recording
- Dynamic driver loading for improved system stability
- Automatic I2C codec detection
- ALSA integration for seamless audio control
- Service-based initialization for proper boot sequencing

## Prerequisites
- Raspberry Pi (any model with 40-pin GPIO header)
- WM8960 Audio HAT hardware
- Raspberry Pi OS (Raspbian) installed
- Internet connection for downloading dependencies
- Basic knowledge of using the terminal
- Root/sudo access

## Installation Steps

### 1. Update System
First, ensure your system is up to date:
```bash
sudo apt update
sudo apt upgrade -y
```

### 2. Install Git
Install Git if not already present:
```bash
sudo apt install git -y
```

### 3. Clone Repository
Clone this repository to your Raspberry Pi:
```bash
git clone https://github.com/MJD19994/WM8960_AudioHAT_Drivers.git
cd WM8960_AudioHAT_Drivers
```

### 4. Make Installation Script Executable
**Important:** You must make the script executable before running it:
```bash
sudo chmod +x install.sh
```

### 5. Run Installation Script
Execute the installation script with root privileges:
```bash
sudo ./install.sh
```

The installation script will:
- Update package lists
- Install required dependencies (Python 3, pip3, git)
- Install Linux kernel headers for your current kernel
- Install the WM8960 driver Python package
- Clean up package cache

### 6. Reboot System
After installation completes, reboot your Raspberry Pi:
```bash
sudo reboot
```

## Verification Procedures

After rebooting, perform the following checks to verify the installation:

### Check 1: Service Status
Verify the WM8960 service is active:
```bash
sudo systemctl status wm8960-soundcard.service
```
**Expected output:** Service should show as "active (exited)" with no errors.

### Check 2: I2C Device Detection
Check if the WM8960 codec is detected on the I2C bus:
```bash
sudo i2cdetect -y 1
```
**Expected output:** You should see "1a" or "UU" at address 0x1a in the grid.

### Check 3: Kernel Module
Verify the sound card driver overlay is loaded:
```bash
lsmod | grep snd_soc
```
**Expected output:** Multiple snd_soc modules should be listed.

### Check 4: Sound Cards
List all available sound cards:
```bash
cat /proc/asound/cards
```
**Expected output:** Should show "wm8960soundcard" among the listed cards.

### Check 5: Playback Devices
Check available playback devices:
```bash
aplay -l
```
**Expected output:** Should list the WM8960 sound card with available playback devices.

### Check 6: Recording Devices
Check available recording devices:
```bash
arecord -l
```
**Expected output:** Should list the WM8960 sound card with available capture devices.

### Check 7: Service Logs
Review the initialization logs for any issues:
```bash
sudo cat /var/log/wm8960-soundcard.log
```
**Expected output:** Log should show successful codec detection and configuration file creation without errors.

## Configuration Files

### /boot/firmware/config.txt

**Important:** Do NOT manually add WM8960 overlay entries to this file!

The `/boot/firmware/config.txt` file is the Raspberry Pi's hardware configuration file. For the WM8960 driver, the overlay is loaded dynamically by the service script, NOT statically in config.txt. This is intentional and crucial for proper operation.

If you previously added lines like:
```
dtoverlay=wm8960-soundcard
```
You should remove them to prevent conflicts with dynamic loading.

### /etc/wm8960-soundcard/asound.conf

This is the ALSA configuration file for the WM8960 sound card. It defines:

- **Default sound card:** Sets WM8960 as the default audio device (card 0)
- **Playback settings:** Configures playback through the dmix plugin for software mixing
- **Mixer control:** Ensures ALSA mixer controls the correct hardware card

The file is symlinked to `/etc/asound.conf` by the initialization service. To customize audio settings, edit this file and restart the service.

### /etc/wm8960-soundcard/wm8960_asound.state

This file stores the ALSA mixer state including:

- Volume levels for playback and capture
- Mute/unmute states for various channels
- Routing configurations
- Hardware-specific control settings

The file is symlinked to `/var/lib/alsa/asound.state` by the initialization service. ALSA automatically restores these settings on boot. To modify:

1. Use `alsamixer` to adjust settings
2. Save with `sudo alsactl store`

## Dynamic Loading Explanation

### Why Dynamic Loading?

The WM8960 driver uses **dynamic loading** instead of static loading in `/boot/firmware/config.txt` for several important reasons:

#### Problems with Static Loading:

1. **Race Conditions:** If the overlay is loaded in config.txt, it loads before the I2C bus is fully initialized, causing detection failures.

2. **Initialization Order:** The codec needs time after boot to be ready on the I2C bus. Static loading doesn't provide this delay.

3. **Boot Failures:** If the hardware isn't connected or has issues, static overlays can cause boot problems or kernel warnings.

4. **No Detection Logic:** Static loading doesn't verify the codec is present before attempting to load drivers.

### How Our Solution Works:

1. **Service-Based Initialization:** The `wm8960-soundcard.service` runs after network-online.target, ensuring proper boot sequence.

2. **I2C Detection:** The service script (`wm8960-soundcard.sh`) actively detects the codec on I2C bus 1 at address 0x1a with multiple retry attempts.

3. **Conditional Loading:** The overlay is only loaded via `dtoverlay` command if the codec is successfully detected.

4. **Configuration Management:** After successful detection, the service creates proper symlinks for ALSA configuration files.

5. **Graceful Failure:** If the codec isn't detected, the service completes without errors, allowing the system to boot normally.

This approach provides:
- More reliable hardware detection
- Better error handling
- Cleaner boot process
- Easier troubleshooting
- Support for hot-plugging (if hardware allows)

## Advanced Configuration

### Adjusting Sample Rates

To change the default sample rate, you can modify the ALSA configuration:

```bash
sudo nano /etc/wm8960-soundcard/asound.conf
```

Add rate conversion parameters to the PCM definition:
```
pcm.!default {
    type plug
    slave {
        pcm "dmix"
        rate 48000
    }
}
```

### Custom Mixer Settings

Use `alsamixer` to adjust audio levels:
```bash
alsamixer
```

Press F6 to select the WM8960 sound card, then adjust:
- PCM playback volume
- Headphone volume
- Speaker volume
- Capture volume (microphone)
- Input source selection

Save your settings:
```bash
sudo alsactl store
```

### Testing Audio Playback

Test speaker output:
```bash
speaker-test -t wav -c 2
```

Play a WAV file:
```bash
aplay /usr/share/sounds/alsa/Front_Center.wav
```

### Testing Audio Recording

Record a 10-second audio sample:
```bash
arecord -d 10 -f cd -t wav test.wav
```

Play back the recording:
```bash
aplay test.wav
```

### Service Management

Enable service to start on boot (usually enabled by default):
```bash
sudo systemctl enable wm8960-soundcard.service
```

Disable service:
```bash
sudo systemctl disable wm8960-soundcard.service
```

Restart service after configuration changes:
```bash
sudo systemctl restart wm8960-soundcard.service
```

## Troubleshooting

### Issue 1: Service Fails to Start

**Symptoms:** Service shows as "failed" in systemctl status

**Solutions:**
1. Check service logs: `sudo journalctl -u wm8960-soundcard.service -n 50`
2. Verify I2C is enabled: `sudo raspi-config` → Interface Options → I2C
3. Check hardware connection and power
4. Review detailed logs: `sudo cat /var/log/wm8960-soundcard.log`

### Issue 2: Codec Not Detected

**Symptoms:** i2cdetect doesn't show device at 0x1a

**Solutions:**
1. Verify HAT is properly seated on GPIO header
2. Check for hardware damage or loose connections
3. Enable I2C manually: Add `dtparam=i2c_arm=on` to `/boot/firmware/config.txt`
4. Reboot and test again
5. Try different I2C address if your HAT uses a different one

### Issue 3: No Sound Output

**Symptoms:** Audio files play but no sound is heard

**Solutions:**
1. Check volume levels: `alsamixer` (press F6 to select WM8960 card)
2. Unmute channels: Press 'M' key in alsamixer
3. Verify correct output device: `aplay -l` then use `-D hw:X,Y` flag
4. Check physical connections to speakers/headphones
5. Test with: `speaker-test -t wav -c 2 -D hw:CARD=wm8960soundcard,DEV=0`

### Issue 4: Wrong Card Order

**Symptoms:** WM8960 is not the default audio device

**Solutions:**
1. Check card order: `cat /proc/asound/cards`
2. Edit `/etc/wm8960-soundcard/asound.conf` to set correct card number
3. Or use device-specific commands: `aplay -D plughw:CARD=wm8960soundcard file.wav`
4. Restart service: `sudo systemctl restart wm8960-soundcard.service`

### Issue 5: Recording Not Working

**Symptoms:** arecord produces empty or silent files

**Solutions:**
1. Select correct input source in alsamixer
2. Increase capture volume (usually low by default)
3. Check input is not muted in alsamixer
4. Verify microphone connection and power (if external)
5. Test with: `arecord -f cd -d 5 test.wav && aplay test.wav`

### Issue 6: Overlay Loading Errors

**Symptoms:** dmesg shows overlay-related errors

**Solutions:**
1. Remove any WM8960 overlay entries from `/boot/firmware/config.txt`
2. Let the service handle dynamic loading only
3. Check kernel version compatibility: `uname -r`
4. Ensure kernel headers match kernel version
5. Reinstall if needed: `sudo ./install.sh`

### Issue 7: Conflicts with Other Audio Devices

**Symptoms:** Multiple audio devices causing conflicts

**Solutions:**
1. Disable on-board audio if not needed: `dtparam=audio=off` in `/boot/firmware/config.txt`
2. Blacklist conflicting modules in `/etc/modprobe.d/blacklist.conf`
3. Set explicit default device in `~/.asoundrc` or `/etc/asound.conf`
4. Reboot after changes

### Issue 8: Service Logs Show Errors

**Symptoms:** Errors visible in /var/log/wm8960-soundcard.log

**Solutions:**
1. Check for I2C errors indicating hardware issues
2. Verify all required kernel modules are available: `lsmod | grep snd`
3. Ensure i2c-tools is installed: `sudo apt install i2c-tools`
4. Check file permissions for config files in `/etc/wm8960-soundcard/`
5. Recreate symlinks manually if broken:
   ```bash
   sudo rm /etc/asound.conf /var/lib/alsa/asound.state
   sudo ln -s /etc/wm8960-soundcard/asound.conf /etc/asound.conf
   sudo ln -s /etc/wm8960-soundcard/wm8960_asound.state /var/lib/alsa/asound.state
   ```

### Issue 9: Audio Quality Problems

**Symptoms:** Crackling, distortion, or stuttering audio

**Solutions:**
1. Lower sample rate in application or ALSA config
2. Increase buffer size parameters
3. Check CPU load: `top` or `htop`
4. Disable unnecessary background services
5. Ensure adequate power supply (quality USB power adapter)
6. Update Raspberry Pi firmware: `sudo rpi-update`

### Issue 10: Python Installation Fails

**Symptoms:** pip3 install command fails during installation

**Solutions:**
1. Verify Python 3 is installed: `python3 --version`
2. Update pip: `sudo pip3 install --upgrade pip`
3. Check for disk space: `df -h`
4. Install build dependencies: `sudo apt install python3-dev build-essential`
5. Check install.sh completed without errors

For additional troubleshooting information, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Uninstallation

To remove the WM8960 drivers from your system:

### 1. Make Uninstallation Script Executable
**Important:** You must make the script executable before running it:
```bash
sudo chmod +x uninstall.sh
```

### 2. Run Uninstallation Script
Execute the uninstallation script with root privileges:
```bash
sudo ./uninstall.sh
```

The uninstallation script will:
- Create a backup of `/boot/firmware/config.txt`
- Remove WM8960-related overlay entries from config.txt
- Display confirmation message

### 3. Manual Cleanup (Optional)

If you want to completely remove all WM8960 files:

```bash
# Stop and disable the service
sudo systemctl stop wm8960-soundcard.service
sudo systemctl disable wm8960-soundcard.service

# Remove service files
sudo rm -f /etc/systemd/system/wm8960-soundcard.service
sudo rm -f /usr/bin/wm8960-soundcard

# Remove configuration files
sudo rm -rf /etc/wm8960-soundcard

# Remove symlinks
sudo rm -f /etc/asound.conf
sudo rm -f /var/lib/alsa/asound.state

# Remove log file
sudo rm -f /var/log/wm8960-soundcard.log

# Reload systemd
sudo systemctl daemon-reload
```

### 4. Reboot
Reboot your system to complete the removal:
```bash
sudo reboot
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

### Getting Help

If you encounter issues:

1. **Check the Troubleshooting Section:** Most common problems are covered above
2. **Review Logs:** Check `/var/log/wm8960-soundcard.log` and `sudo journalctl -u wm8960-soundcard.service`
3. **Search Issues:** Look through existing [GitHub Issues](https://github.com/MJD19994/WM8960_AudioHAT_Drivers/issues)
4. **Open an Issue:** Create a new issue with:
   - Raspberry Pi model and OS version
   - Output of verification checks
   - Relevant log files
   - Description of the problem

### Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

### Resources

- [WM8960 Datasheet](https://www.cirrus.com/products/wm8960/)
- [Raspberry Pi Documentation](https://www.raspberrypi.org/documentation/)
- [ALSA Project](https://www.alsa-project.org/)

### Credits

Developed and maintained by the community. Special thanks to all contributors who have helped improve this driver package.
