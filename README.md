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

Before installing the WM8960 Audio HAT drivers, ensure you have:

- **Hardware:**
  - Raspberry Pi (any model with 40-pin GPIO header)
  - WM8960 Audio HAT hardware properly seated on GPIO pins
  
- **Software:**
  - Raspberry Pi OS (Raspbian) installed (32-bit or 64-bit)
  - Internet connection for downloading dependencies
  - Root/sudo access
  
- **System Preparation:**

First, update your system and install git:

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install git -y
```

**Note:** The `apt update` and `apt upgrade` steps are essential for ensuring your kernel and package database are current before driver installation.

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
1. Update package lists with `apt update`
2. Install Linux kernel headers for the current kernel (`linux-headers-$(uname -r)`)
3. Install DKMS (Dynamic Kernel Module Support)
4. Install required packages: git, i2c-tools, and ALSA plugins
5. Clone and compile the wm8960-soundcard kernel module via DKMS
6. Copy the device tree overlay to `/boot/overlays/`
7. Configure kernel modules in `/etc/modules` (add i2c-dev)
8. Enable I2C and I2S in `/boot/firmware/config.txt`
9. Install ALSA configuration files to `/etc/wm8960-soundcard/`
10. Install the systemd service script to `/usr/bin/wm8960-soundcard`
11. Install and enable the systemd service

**Note:** The script does NOT add `dtoverlay=wm8960-soundcard` to config.txt - the overlay is loaded dynamically by the service for better reliability.

### 6. Reboot System
After installation completes, reboot your Raspberry Pi:
```bash
sudo reboot
```

## Verification Procedures

After rebooting, perform the following checks to verify the installation. All seven checks should pass for a successful installation:

### Check 1: Service Status
Verify the WM8960 service is active and loaded successfully:
```bash
sudo systemctl status wm8960-soundcard.service
```
**Expected output:** 
- Service should show as "active (exited)" with green dot
- Status should indicate "Loaded: loaded" and "Active: active (exited)"
- No error messages in the service log output
- Example: `Active: active (exited) since ...`

### Check 2: I2C Device Detection
Check if the WM8960 codec is detected on the I2C bus:
```bash
sudo i2cdetect -y 1
```
**Expected output:** 
- A grid showing I2C addresses
- You should see "1a" or "UU" at address 0x1a (row 10, column a)
- "1a" means device detected but not in use by a driver
- "UU" means device detected and in use by a driver (preferred)
- Example:
  ```
       0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
  00:          -- -- -- -- -- -- -- -- -- -- -- -- -- 
  10: -- -- -- -- -- -- -- -- -- -- UU -- -- -- -- -- 
  20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
  ```

### Check 3: Kernel Module
Verify the sound card driver modules are loaded:
```bash
lsmod | grep snd_soc
```
**Expected output:** 
- Multiple snd_soc modules should be listed
- Should include entries like:
  - `snd_soc_wm8960` - The WM8960 codec driver
  - `snd_soc_core` - ALSA SoC core
  - `snd_soc_bcm2835_i2s` - Raspberry Pi I2S interface
- Example:
  ```
  snd_soc_wm8960_soundcard    16384  0
  snd_soc_wm8960             40960  1
  snd_soc_bcm2835_i2s        20480  2
  snd_soc_core              200000  3
  ```

### Check 4: Sound Cards
List all available sound cards:
```bash
cat /proc/asound/cards
```
**Expected output:** 
- Should show "wm8960soundcard" in the list
- Typically appears as card 0, 1, or 2 depending on other audio hardware
- Example:
  ```
   0 [vc4hdmi       ]: vc4-hdmi - vc4-hdmi
                      vc4-hdmi
   1 [wm8960soundcard]: wm8960-soundcard - wm8960-soundcard
                      wm8960-soundcard
  ```

### Check 5: Playback Devices
Check available playback (speaker/headphone) devices:
```bash
aplay -l
```
**Expected output:** 
- Should list the WM8960 sound card with available playback devices
- Shows card number, device number, and subdevices
- Example:
  ```
  card 1: wm8960soundcard [wm8960-soundcard], device 0: bcm2835-i2s-wm8960-hifi wm8960-hifi-0 [bcm2835-i2s-wm8960-hifi wm8960-hifi-0]
    Subdevices: 1/1
    Subdevice #0: subdevice #0
  ```

### Check 6: Recording Devices
Check available recording (microphone) devices:
```bash
arecord -l
```
**Expected output:** 
- Should list the WM8960 sound card with available capture devices
- Shows card number and capture capabilities
- Example:
  ```
  card 1: wm8960soundcard [wm8960-soundcard], device 0: bcm2835-i2s-wm8960-hifi wm8960-hifi-0 [bcm2835-i2s-wm8960-hifi wm8960-hifi-0]
    Subdevices: 1/1
    Subdevice #0: subdevice #0
  ```

### Check 7: Service Logs
Review the initialization logs for any issues:
```bash
sudo cat /var/log/wm8960-soundcard.log
```
**Expected output:** 
- Log should show successful codec detection at I2C address 0x1a
- Should contain "install wm8960-soundcard" message
- Should show successful configuration file creation
- Should end with "WM8960 service initialization complete"
- No error messages or warnings about missing devices
- Example log entries:
  ```
  + i2cdetect -y 1 0x1a 0x1a
  + is_1a=1a
  + echo 'install wm8960-soundcard'
  install wm8960-soundcard
  + dtoverlay wm8960-soundcard
  + echo 'create wm8960-soundcard configure file'
  create wm8960-soundcard configure file
  + echo WM8960 service initialization complete
  WM8960 service initialization complete
  ```

### Additional Check: DKMS Status
Verify the DKMS module is properly installed:
```bash
sudo dkms status
```
**Expected output:**
- Should show wm8960-soundcard module installed for your kernel version
- Example:
  ```
  wm8960-soundcard/1.0, 5.15.84-v8+, aarch64: installed
  ```

If all seven checks pass, your WM8960 Audio HAT is properly installed and ready to use!

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

To completely remove the WM8960 drivers and all related files from your system:

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
1. Stop and disable the wm8960-soundcard systemd service
2. Remove systemd service files from `/etc/systemd/system/` and `/usr/bin/`
3. Remove ALSA configuration symlinks (`/etc/asound.conf`, `/var/lib/alsa/asound.state`)
4. Remove the ALSA configuration directory (`/etc/wm8960-soundcard/`)
5. Remove the service log file (`/var/log/wm8960-soundcard.log`)
6. Remove the DKMS kernel module
7. Remove DKMS source files from `/usr/src/wm8960-soundcard-1.0/`
8. Remove the device tree overlay from `/boot/overlays/`
9. Clean up any WM8960 entries from `/boot/firmware/config.txt` (with backup)

### 3. Manual Cleanup (Optional)

The uninstallation script preserves some system-level settings that may be used by other software. If you want to completely remove everything:

```bash
# Remove I2C and I2S parameters from config.txt (edit manually)
sudo nano /boot/firmware/config.txt
# Remove lines: dtparam=i2c_arm=on and dtparam=i2s=on

# Remove i2c-dev from /etc/modules (edit manually)
sudo nano /etc/modules
# Remove line: i2c-dev

# Optionally remove packages (only if not needed by other software)
sudo apt-get remove --purge dkms i2c-tools libasound2-plugins
sudo apt-get autoremove
```

### 4. Reboot
Reboot your system to complete the removal:
```bash
sudo reboot
```

After rebooting, verify the removal:
- Check DKMS status: `sudo dkms status` (should not show wm8960-soundcard)
- Check sound cards: `cat /proc/asound/cards` (should not show wm8960soundcard)
- Check service status: `sudo systemctl status wm8960-soundcard.service` (should show "not found")

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
