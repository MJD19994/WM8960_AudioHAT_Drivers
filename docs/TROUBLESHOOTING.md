# Troubleshooting Guide for WM8960 Audio HAT Drivers

This document provides a comprehensive troubleshooting guide for common issues with the WM8960 Audio HAT drivers.

## Quick Diagnostics

Before diving into specific issues, run the diagnostic tools:

```bash
# 8 automated checks (skips interactive speaker/mic tests — good for CI/headless)
sudo bash test-audio.sh --quick

# Full 10-check test (adds interactive speaker and mic verification)
sudo bash test-audio.sh

# Full system diagnostic dump (paste into GitHub issues)
sudo wm8960-diag

# Service log
sudo cat /var/log/wm8960-soundcard.log
```

---

## 0. Device Tree Overlay Driver Conflict (RESOLVED)

**Status:** Resolved in the current version of the driver.

**Historical Context:** Earlier versions registered as `asoc-simple-card`, which conflicted with Raspberry Pi's built-in simple-audio-card driver:
```text
Error: Driver 'asoc-simple-card' is already registered, aborting...
```

**Current Solution:** The driver now uses `asoc-wm8960-soundcard`, eliminating naming conflicts. If you're upgrading from an older version and still see this error:

```bash
sudo bash uninstall.sh
sudo bash install.sh
sudo reboot
dmesg | grep wm8960    # should show 'asoc-wm8960-soundcard'
```

## 1. Service Failures

**Symptoms:** `systemctl status wm8960-soundcard.service` shows failed state.

**Diagnosis:**
```bash
sudo systemctl status wm8960-soundcard.service
sudo journalctl -u wm8960-soundcard.service -n 50
sudo cat /var/log/wm8960-soundcard.log
```

**Solution:**
```bash
sudo systemctl restart wm8960-soundcard.service
```

If the service fails repeatedly, check:
- Missing kernel modules: `lsmod | grep snd_soc_wm8960`
- I2C detection: `sudo i2cdetect -y 1` (should show device at `0x1a`)
- DKMS build status: `sudo dkms status`
- Hardware connection and power

## 2. Codec Not Detected

**Symptoms:** `aplay -l` shows no `wm8960soundcard`, or `i2cdetect` doesn't show a device at `0x1a`.

**Diagnosis:**
```bash
aplay -l
sudo i2cdetect -y 1
dmesg | grep wm8960
```

**Solution:**
- Ensure the HAT is firmly seated on the GPIO header
- Check I2C is enabled: `grep dtparam=i2c_arm /boot/firmware/config.txt`
- Verify the overlay is loaded: `sudo dtoverlay -l | grep wm8960-soundcard`
- If you just did a kernel update, the DKMS module may need rebuilding — restart the service to trigger auto-rebuild

## 3. Audio Broke After Kernel Update

**Symptoms:** Audio was working, then stopped after `apt upgrade` and reboot. `dmesg` shows `No MCLK configured`.

**Cause:** The DKMS module wasn't rebuilt for the new kernel. Raspberry Pi OS packaging can trigger a race where the DKMS hook fires during kernel image install (before headers exist), silently skips the build, and no hook retriggers DKMS when headers install seconds later.

**Diagnosis:**
```bash
sudo dkms status
uname -r
sudo cat /var/log/wm8960-soundcard.log
```

**Solution:**

1. **Automatic path (preferred):** The service script detects a missing DKMS build at boot and rebuilds automatically. Just reboot:
   ```bash
   sudo reboot
   ```
   First boot after a kernel update takes ~30 seconds longer while the module compiles (on Pi Zero 2W).

2. **Check the service log** for what the auto-rebuild did:
   ```bash
   sudo cat /var/log/wm8960-soundcard.log
   ```
   - If you see **"DKMS auto-rebuild completed successfully"**, the service fixed it automatically. A second reboot should work.
   - If you see **"Kernel headers not found"**, install them and restart the service:
     ```bash
     sudo apt install linux-headers-$(uname -r)
     sudo systemctl restart wm8960-soundcard.service
     ```
   - If you see **"DKMS build failed"**, the build log at `/var/lib/dkms/wm8960-soundcard/1.0/build/make.log` has the compiler error.

3. **Manual rebuild** if the auto-rebuild path isn't working:
   ```bash
   sudo apt install linux-headers-$(uname -r)
   sudo dkms install wm8960-soundcard/1.0 -k $(uname -r)
   sudo reboot
   ```

4. **Verify:** `sudo dkms status` should show your kernel version as "installed":
   ```text
   wm8960-soundcard/1.0, 6.12.75+rpt-rpi-v8, aarch64: installed
   ```

**Prevention:** The service script automatically detects and rebuilds the DKMS module on boot if needed. This adds ~30 seconds to boot time only when a rebuild is required. To avoid it entirely, always reboot before re-installing after a kernel upgrade (so DKMS builds for the running kernel, not the previous one).

## 4. No Sound Output

**Symptoms:** Audio files play (no errors) but no sound is heard from the speaker/headphones.

**Diagnosis:**
```bash
amixer -c wm8960soundcard sget 'Speaker Playback Volume'
amixer -c wm8960soundcard sget 'Headphone Playback Volume'
alsamixer -c wm8960soundcard    # interactive check
```

**Solution:**
- Adjust volume levels and unmute channels in `alsamixer -c wm8960soundcard` (press M to unmute)
- Use the volume preset utility: `sudo wm8960-volume speakers` or `sudo wm8960-volume headphones`
- Verify the DAC is enabled: check `Left DAC` and `Right DAC` are unmuted
- Reset to known-good defaults: `sudo wm8960-volume reset`
- Test with: `speaker-test -t wav -c 2 -D hw:CARD=wm8960soundcard,DEV=0`
- Check physical connections to speakers/headphones

## 5. Wrong Card Order

**Symptoms:** WM8960 is not the default audio device; other apps pick HDMI or headphone jack.

**Diagnosis:**
```bash
cat /proc/asound/cards
```

**Solution:** The installer deploys `/etc/asound.conf` (symlinked to `/etc/wm8960-soundcard/asound.conf`) which sets `wm8960soundcard` as the default ALSA device.

- Check for conflicting configs in `~/.asoundrc` and remove them
- For PipeWire/PulseAudio, verify the default sink/source in their dedicated READMEs
- Use device-specific commands to bypass the default: `aplay -D plughw:CARD=wm8960soundcard file.wav`

## 6. Recording Not Working

**Symptoms:** `arecord` produces empty or silent files.

**Diagnosis:**
```bash
arecord -l
arecord -D default -c 2 -r 16000 -f S16_LE -d 5 /tmp/test.wav
aplay /tmp/test.wav
```

**Solution:**
- Ensure the capture path is enabled in `alsamixer` (Left/Right Input Mixer switches)
- Use the recording preset: `sudo wm8960-volume recording`
- Check the correct input source is selected (LINPUT1/RINPUT1 for onboard mics)
- Increase capture volume (usually low by default)
- Check input is not muted in alsamixer

## 7. Overlay Loading Errors

**Symptoms:** `dmesg` shows overlay-related errors.

**Diagnosis:**
```bash
dmesg | grep -iE "wm8960|overlay|error"
ls /boot/firmware/overlays/wm8960-soundcard.dtbo
sudo dtoverlay -l
```

**Solution:**
- Verify the overlay file exists in `/boot/firmware/overlays/`
- Check the service loaded it dynamically: `sudo dtoverlay -l | grep wm8960-soundcard`
- **Remove any manual** `dtoverlay=wm8960-soundcard` **entries from config.txt** — the service loads it dynamically after I2C detection for reliability
- Check kernel version compatibility: `uname -r` and ensure kernel headers match
- Reinstall if needed: `sudo bash install.sh`

## 8. ALSA Warnings

**Diagnosis:** Look for warnings in dmesg or service log:
```bash
dmesg | grep -i alsa
sudo cat /var/log/wm8960-soundcard.log
```

**Solution:** Most ALSA warnings are non-fatal. Common ones:
- **"Unknown field" in state restore** — state file references a control not present on the current driver version. Run `sudo wm8960-volume reset` to regenerate.
- **Underrun warnings during playback** — lower the sample rate or increase buffer sizes (see Section 11, Audio Quality).

## 8a. ALSA Mixer Settings Not Applied

**Symptoms:** Volume/mute settings don't persist or apply after reboot; `alsactl restore` shows warnings about unknown controls; wrong card index in state file.

**Root Cause:** ALSA state file format is incorrect or references wrong card index.

**Solution:**

1. **Check ALSA state file format:**
   ```bash
   head -20 /var/lib/alsa/asound.state
   ```
   Should start with `state.wm8960soundcard {` (not XML format!)

2. **Verify card name:**
   ```bash
   cat /proc/asound/cards    # should show 'wm8960soundcard'
   ```

3. **If state file is wrong format, reinstall:**
   ```bash
   sudo systemctl stop wm8960-soundcard.service
   sudo rm /var/lib/alsa/asound.state /etc/asound.conf
   sudo systemctl start wm8960-soundcard.service
   ```

4. **Manually restore from backup:**
   ```bash
   sudo alsactl restore -f /etc/wm8960-soundcard/wm8960_asound.state
   ```

5. **Recreate symlinks** if they're broken:
   ```bash
   sudo rm /etc/asound.conf /var/lib/alsa/asound.state
   sudo ln -s /etc/wm8960-soundcard/asound.conf /etc/asound.conf
   sudo ln -s /etc/wm8960-soundcard/wm8960_asound.state /var/lib/alsa/asound.state
   ```

6. **Adjust and save new settings:**
   ```bash
   alsamixer              # adjust volumes
   sudo alsactl store     # save settings
   ```

## 9. Module Loading Issues

**Symptoms:** `lsmod | grep snd_soc_wm8960` shows no modules or only one.

**Diagnosis:**
```bash
lsmod | grep snd_soc_wm8960
# Expected: both snd_soc_wm8960 (codec) and snd_soc_wm8960_soundcard (machine driver)
sudo dkms status
```

**Solution:**
```bash
sudo modprobe snd_soc_wm8960
sudo modprobe snd_soc_wm8960_soundcard
```

If modules fail to load, check DKMS status. If the module isn't built for the running kernel, restart the service to trigger auto-rebuild:
```bash
sudo systemctl restart wm8960-soundcard.service
```

## 10. Conflicts with Other Audio Devices

**Symptoms:** Multiple audio devices (HDMI, onboard audio, USB sound cards) causing confusion.

**Solution:**
- **Disable onboard audio** if not needed: add `dtparam=audio=off` to `/boot/firmware/config.txt`
- **Blacklist conflicting modules** in `/etc/modprobe.d/blacklist.conf` (e.g., `blacklist snd_bcm2835` to disable HDMI audio)
- **Set explicit default device** in `~/.asoundrc` if app-specific
- Reboot after changes

## 11. Audio Quality Problems

**Symptoms:** Crackling, distortion, or stuttering audio.

**Solution:**
- **Lower sample rate:** try 16000 or 44100 instead of 48000
- **For distortion at high volumes:** reduce speaker volume and use Class D boost instead
- **Enable zero-cross detection** to prevent pops: `sudo wm8960-volume headphones`
- **For recording quality:** enable the hardware high-pass filter to remove DC offset
- **Increase buffer sizes:** uncomment the `period_size`/`buffer_size` hints in `/etc/wm8960-soundcard/asound.conf`
- **Check CPU load:** `top` or `htop` — high load causes underruns
- **Ensure adequate power supply** — quality USB power adapter, thick cable
- **Ensure system is up to date:** `sudo apt update && sudo apt upgrade`

## 12. General Tips

- Run `sudo bash test-audio.sh` for the full 10-check diagnostic (8 automated + 2 interactive speaker/mic tests)
- Use `sudo bash test-audio.sh --quick` for the 8 automated checks only (non-interactive, CI/headless safe)
- Run `sudo wm8960-diag` for a comprehensive system dump (ready to paste into a GitHub issue)
- Check the service log: `sudo cat /var/log/wm8960-soundcard.log`
- After any kernel update, reboot to trigger the DKMS auto-rebuild
- For advanced mixer tuning, see [ALSA-Mixer-Controls.md](ALSA-Mixer-Controls.md)

For further assistance, open an issue on the [GitHub repository](https://github.com/MJD19994/WM8960_AudioHAT_Drivers/issues) — please include the output of `sudo wm8960-diag`.
