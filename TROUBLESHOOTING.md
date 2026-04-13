# Troubleshooting Guide for WM8960 AudioHAT Drivers

This document provides a comprehensive troubleshooting guide for common issues encountered with the WM8960 AudioHAT drivers.

## 0. Device Tree Overlay Driver Conflict (RESOLVED)
**Status:** This issue has been resolved in the current version of the driver.

**Historical Context:**
Earlier versions of the WM8960 driver registered as `asoc-simple-card`, which conflicted with Raspberry Pi's built-in simple-audio-card driver for the default `/sound` node. This caused the error:
```
Error: Driver 'asoc-simple-card' is already registered, aborting...
```

**Current Solution:**
The driver now uses a unique platform driver name `asoc-wm8960-soundcard`, eliminating any naming conflicts with built-in drivers. No workarounds or manual configuration are needed.

If you're upgrading from an older version and still see this error:
1. **Reinstall the driver completely:**
   ```bash
   sudo ./uninstall.sh
   sudo ./install.sh
   sudo reboot
   ```

2. **Verify the driver name in dmesg:**
   ```bash
   dmesg | grep wm8960
   ```
   You should see references to `asoc-wm8960-soundcard`, not `asoc-simple-card`.

## 1. Service Failures
**Diagnosis:** Check the WM8960 service status and logs:
```bash
sudo systemctl status wm8960-soundcard.service
sudo cat /var/log/wm8960-soundcard.log
```

**Solution:** Restart the service:
```bash
sudo systemctl restart wm8960-soundcard.service
```

If the service fails repeatedly, check for:
- Missing kernel modules: `lsmod | grep snd_soc_wm8960`
- I2C detection failure: `sudo i2cdetect -y 1` (should show device at address `0x1a`)
- DKMS build issues: `dkms status`

## 2. Codec Detection Issues
**Diagnosis:** Verify if the codec is detected:
```bash
aplay -l
sudo i2cdetect -y 1
```
The WM8960 should appear at I2C address `0x1a`. If `aplay -l` shows no `wm8960soundcard`, the codec is not being detected.

**Solution:**
- Ensure the HAT is firmly seated on the GPIO header
- Check that I2C is enabled: `grep dtparam=i2c_arm /boot/firmware/config.txt`
- Verify the overlay is loaded: `dmesg | grep wm8960`
- If using a fresh kernel, the DKMS module may need rebuilding — restart the service to trigger auto-rebuild

## 3. Wrong Card Order
**Diagnosis:** Check the order of sound cards:
```bash
cat /proc/asound/cards
```

**Solution:** The installer deploys `/etc/asound.conf` which sets `wm8960soundcard` as the default ALSA device. If another application overrides this, check for conflicting configs in `~/.asoundrc` and remove them.

## 4. No Sound
**Diagnosis:** Ensure volume is up and not muted:
```bash
amixer -c wm8960soundcard sget 'Speaker Playback Volume'
amixer -c wm8960soundcard sget 'Headphone Playback Volume'
```

**Solution:**
- Use `alsamixer -c wm8960soundcard` to adjust volume levels and unmute channels
- Use the volume preset utility: `wm8960-volume speakers` or `wm8960-volume headphones`
- Verify the DAC is enabled: check that `Left DAC` and `Right DAC` are unmuted in alsamixer
- Reset to known-good defaults: `wm8960-volume reset`

## 5. Recording Problems
**Diagnosis:** Check the recording device:
```bash
arecord -l
arecord -D default -c 2 -r 16000 -f S16_LE -d 5 /tmp/test.wav
```

**Solution:**
- Ensure the capture path is enabled in alsamixer (Left/Right Input Mixer switches)
- Use the recording preset: `wm8960-volume recording`
- Check that the correct input source is selected (LINPUT1/RINPUT1 for onboard mics)

## 6. Overlay Errors
**Diagnosis:** Check if the overlay is loaded correctly:
```bash
dmesg | grep wm8960
ls /boot/firmware/overlays/wm8960-soundcard.dtbo
```

**Solution:**
- Verify the overlay file exists in `/boot/firmware/overlays/`
- Check that the service loaded the overlay dynamically: `sudo dtoverlay -l | grep wm8960-soundcard`
- If the overlay fails to load, check for conflicts: `dmesg | grep -i error`

## 7. ALSA Warnings
**Diagnosis:** Look for warnings in dmesg or the service log:
```bash
dmesg | grep -i alsa
sudo cat /var/log/wm8960-soundcard.log
```

**Solution:** Most ALSA warnings are non-fatal. Common warnings include:
- "Unknown field" in state restore — usually means the state file references a control not present on the current driver version. Run `wm8960-volume reset` to regenerate.
- Underrun warnings during playback — increase buffer sizes or lower sample rate.

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
   head -20 /var/lib/alsa/asound.state
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
**Diagnosis:** Check if the WM8960 modules are loaded:
```bash
lsmod | grep snd_soc_wm8960
```
You should see both `snd_soc_wm8960` (codec) and `snd_soc_wm8960_soundcard` (machine driver).

**Solution:**
```bash
sudo modprobe snd_soc_wm8960
sudo modprobe snd_soc_wm8960_soundcard
```

If modules fail to load, check DKMS:
```bash
dkms status
```
If the module is not built for the running kernel, restart the service to trigger auto-rebuild:
```bash
sudo systemctl restart wm8960-soundcard.service
```

## 9. Audio Quality Issues
**Diagnosis:** Identify if there are stuttering or distortion artifacts.

**Solution:**
- Lower the sample rate: try 16000 or 44100 instead of 48000
- For distortion at high volumes, reduce speaker volume and use Class D boost instead
- Enable zero-cross detection to prevent pops: `wm8960-volume headphones`
- For recording quality, enable the hardware high-pass filter to remove DC offset and low-frequency noise

## 10. DKMS Module Not Built After Kernel Update
**Diagnosis:** After a kernel update, audio stops working.
```bash
dkms status
uname -r
```
If DKMS shows the module is not built for the running kernel version:

**Root Cause:** Raspberry Pi OS installs the kernel image before headers. The DKMS hook fires during image install, finds no headers, and silently skips the build. When headers install seconds later, no hook retriggers DKMS.

**Solution:** The service automatically detects and rebuilds the DKMS module at boot. Simply reboot:
```bash
sudo reboot
```
The first boot after a kernel update may take ~30 seconds longer while the module compiles (on Pi Zero 2W).

## 11. General Tips
- Run `sudo bash test-audio.sh` for an automated 10-check diagnostic run
- Use `sudo ./test-audio.sh --quick` for non-interactive CI/headless testing
- Check the service log for timestamped diagnostics: `sudo cat /var/log/wm8960-soundcard.log`
- Ensure your system is up to date: `sudo apt update && sudo apt upgrade`
- After any kernel update, reboot to allow the DKMS auto-rebuild

For further assistance, open an issue on the [GitHub repository](https://github.com/MJD19994/WM8960_AudioHAT_Drivers/issues).
