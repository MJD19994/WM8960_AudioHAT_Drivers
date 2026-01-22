# Troubleshooting Guide for WM8960 AudioHAT Drivers

This document provides a comprehensive troubleshooting guide for common issues encountered with the WM8960 AudioHAT drivers.

## 0. Device Tree Overlay Driver Conflict (CRITICAL)
**Diagnosis:** Check dmesg for driver registration errors:
```bash
dmesg | grep "asoc-simple-card"
```
**Symptoms:** 
- Error message: `Error: Driver 'asoc-simple-card' is already registered, aborting...`
- Module `snd_soc_wm8960_soundcard` fails to load
- `lsmod | grep wm8960` shows no WM8960 modules
- Audio playback doesn't work

**Root Cause:** The WM8960 driver registers as `asoc-simple-card`, which conflicts with Raspberry Pi's built-in simple-audio-card driver for the default `/sound` node.

**Solution:** This should be automatically handled by the installation. If you still see this error:

1. **Remove WM8960 overlay from config.txt** (if manually added):
   ```bash
   sudo nano /boot/firmware/config.txt
   # Remove or comment out any line containing: dtoverlay=wm8960-soundcard
   ```

2. **Ensure I2S-MMAP is configured** (not dtparam=i2s):
   ```bash
   grep -E "i2s|i2c" /boot/firmware/config.txt
   ```
   Should show:
   ```
   dtparam=i2c_arm=on
   dtoverlay=i2s-mmap
   ```
   If you see `dtparam=i2s=on` instead, replace it with `dtoverlay=i2s-mmap`

3. **Check service logs** for conflict resolution:
   ```bash
   sudo cat /var/log/wm8960-soundcard.log
   ```
   Should show: `Disabling default /sound node to prevent driver conflict...`

4. **Restart the service**:
   ```bash
   sudo systemctl restart wm8960-soundcard.service
   ```

5. **If problem persists, reinstall**:
   ```bash
   sudo ./uninstall.sh
   sudo ./install.sh
   sudo reboot
   ```

## 1. Service Failures
**Diagnosis:** Check system logs for errors related to audio services.  
**Solution:** Restart the audio service with the following command:
```bash
sudo systemctl restart audio.service
```

## 2. Codec Detection Issues
**Diagnosis:** Verify if the codec is detected by running `aplay -l`.  
**Solution:** If not detected, check connections and re-flash the firmware if necessary.

## 3. Wrong Card Order
**Diagnosis:** Use `cat /proc/asound/cards` to check the order of sound cards.  
**Solution:** Configure `/etc/asound.conf` or `~/.asoundrc` to set the default card.

## 4. No Sound
**Diagnosis:** Ensure volume is up and not muted.  
**Solution:** Use `alsamixer` to adjust the volume levels and unmute channels.

## 5. Recording Problems
**Diagnosis:** Check the recording device settings with `arecord -l`.  
**Solution:** Ensure the correct recording source is selected in the application settings.

## 6. Overlay Errors
**Diagnosis:** Overlay errors can often be attributed to incorrect configuration.  
**Solution:** Check the overlay settings in the device tree and adjust as needed.

## 7. ALSA Warnings
**Diagnosis:** Look for warnings in the output of `dmesg` or `journalctl -xe`.  
**Solution:** Update ALSA packages or reconfigure audio settings.

## 7a. ALSA Mixer Settings Not Applied
**Diagnosis:** Mixer settings (volume, mute, etc.) don't persist or apply after reboot.
**Symptoms:**
- Volume is too low or muted after reboot
- `alsactl restore` shows warnings about unknown controls
- Wrong card index referenced in state file

**Root Cause:** ALSA state file format is incorrect or references wrong card index.

**Solution:**
1. **Check ALSA state file format**:
   ```bash
   cat /var/lib/alsa/asound.state | head -20
   ```
   Should start with `state.wm8960soundcard {` (not XML format!)

2. **Verify card name**:
   ```bash
   cat /proc/asound/cards
   ```
   Note the card name (should be `wm8960soundcard`)

3. **If state file is wrong format, reinstall**:
   ```bash
   sudo systemctl stop wm8960-soundcard.service
   sudo rm /var/lib/alsa/asound.state /etc/asound.conf
   sudo systemctl start wm8960-soundcard.service
   ```

4. **Manually restore from backup**:
   ```bash
   sudo alsactl restore -f /etc/wm8960-soundcard/wm8960_asound.state
   ```

5. **Adjust and save new settings**:
   ```bash
   alsamixer  # Adjust volumes
   sudo alsactl store  # Save settings
   ```

## 8. Module Loading Issues
**Diagnosis:** Check if the WM8960 module is loaded with `lsmod | grep wm8960`.  
**Solution:** Load the module with:
```bash
sudo modprobe wm8960
```

## 9. Audio Quality Issues
**Diagnosis:** Identify if there are stuttering or distortion artifacts.
**Solution:** Lower the sample rate or increase buffer sizes in the audio playback settings.

## 10. General Tips
- Ensure your system is up to date with the latest kernel and libraries.  
- Refer to the official documentation for any specific driver configurations.  

For further assistance, consult the user forums or the community support channels.