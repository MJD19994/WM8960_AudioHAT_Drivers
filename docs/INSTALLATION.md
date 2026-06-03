# Installation Guide

Detailed installation, verification, and uninstallation instructions for the WM8960 Audio HAT drivers. For a quick-start summary, see the [main README](../README.md).

## Contents

- [Prerequisites](#prerequisites)
- [Installation Steps](#installation-steps)
- [Installer Options](#installer-options)
- [Manual Verification](#manual-verification)
- [Uninstallation](#uninstallation)

---

## Prerequisites

**Hardware:**
- Raspberry Pi (any model with 40-pin GPIO header)
- WM8960 Audio HAT properly seated on GPIO pins

**Software:**
- Raspberry Pi OS (32-bit or 64-bit, Trixie or newer recommended)
- Internet connection for downloading dependencies
- Root/sudo access

## Installation Steps

### 1. Update System and Reboot

Ensure your system is fully updated, then **reboot before installing**:

```bash
sudo apt update
sudo apt upgrade -y
sudo reboot
```

> **Why reboot first?** The install script builds the kernel module for the *running* kernel. If you upgrade the kernel and install without rebooting, the module gets built for the old kernel. On the next boot into the new kernel, the service will auto-rebuild the DKMS module (~30s extra boot time), but audio will still not work until a **second reboot** loads the freshly built module. Rebooting first avoids this entirely.

### 2. Install Git

```bash
sudo apt install git -y
```

### 3. Clone Repository

Make sure you're in your home directory before cloning so the uninstall section below can reach the repo at `~/WM8960_AudioHAT_Drivers`:

```bash
cd ~
git clone https://github.com/MJD19994/WM8960_AudioHAT_Drivers.git
cd WM8960_AudioHAT_Drivers
```

### 4. Run the Installer

```bash
sudo bash install.sh
```

The installation script performs 13 steps:

1. Update package lists
2. Install kernel headers
3. Install required packages (DKMS, i2c-tools, alsa-utils, ALSA plugins) and configure I2C in config.txt
4. Compile and install the `wm8960-soundcard` kernel module via DKMS
5. Copy the device tree overlay to `/boot/firmware/overlays/`
6. Configure kernel modules in `/etc/modules` (add `i2c-dev`)
7. Enable I2S-MMAP overlay in config.txt
8. Install ALSA configuration files, version info, and PipeWire/PulseAudio configs (if detected)
9. Install systemd service script, volume utility, and diagnostic tool
10. Install systemd service file and logrotate config
11. Install ALSA auto-save components (disabled by default)
12. Enable the systemd service
13. Validate the installation (DKMS, overlay, service, ALSA, config.txt)

A pre-flight check warns if a kernel update is pending reboot.

> **Note:** The script does NOT add `dtoverlay=wm8960-soundcard` to config.txt — the overlay is loaded dynamically by the service for reliability. See [CONFIGURATION.md](CONFIGURATION.md#dynamic-loading-explanation) for details.

### 5. Reboot

```bash
sudo reboot
```

## Installer Options

```bash
sudo bash install.sh --help
```

| Flag | Purpose |
|------|---------|
| `--skip-pipewire` | Skip PipeWire/WirePlumber configuration |
| `--skip-pulseaudio` | Skip PulseAudio configuration |
| `--yes`, `-y` | Auto-confirm prompts and skip the automatic reboot prompt (manual reboot still required for the driver to take effect) |
| `--help`, `-h` | Show usage help |

## Manual Verification

After rebooting, the fastest way to verify your installation is the automated test script:

```bash
sudo bash test-audio.sh           # full 10-check test (8 automated + 2 interactive)
sudo bash test-audio.sh --quick   # 8 automated checks only (skips speaker/mic tests)
```

If you prefer to check things individually, the following seven checks should all pass:

### Check 1: Service Status

Verify the WM8960 service is active and loaded successfully:

```bash
sudo systemctl status wm8960-soundcard.service
```

**Expected output:**
- Service shows as `active (exited)` with a green dot
- Status indicates `Loaded: loaded` and `Active: active (exited)`
- No error messages in the service log output
- Example: `Active: active (exited) since ...`

The service is `Type=oneshot`, so `active (exited)` is the correct state — it ran, did its work, and exited successfully.

### Check 2: I2C Device Detection

Check if the WM8960 codec is detected on the I2C bus:

```bash
sudo i2cdetect -y 1
```

**Expected output:**
- A grid showing I2C addresses
- `UU` (device in use by a driver) or `1a` (device detected but not in use) at row 10, column a
- `UU` is preferred — it confirms the driver has claimed the codec

**Example:**

```text
     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
00:                         -- -- -- -- -- -- -- --
10: -- -- -- -- -- -- -- -- -- -- UU -- -- -- -- --
20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
```

### Check 3: Kernel Modules

Verify the sound card driver modules are loaded:

```bash
lsmod | grep snd_soc
```

**Expected:** Multiple `snd_soc` modules should be listed, including:
- `snd_soc_wm8960_soundcard` — the WM8960 machine driver
- `snd_soc_wm8960` — the WM8960 codec driver
- `snd_soc_core` — ALSA SoC core
- `snd_soc_bcm2835_i2s` — Raspberry Pi I2S interface

**Example:**

```text
snd_soc_wm8960_soundcard    16384  0
snd_soc_wm8960              40960  1
snd_soc_bcm2835_i2s         20480  2
snd_soc_core               200000  3
```

### Check 4: Sound Cards

List all available sound cards:

```bash
cat /proc/asound/cards
```

**Expected:** `wm8960soundcard` should appear in the list. Typically appears as card 0, 1, or 2 depending on other audio hardware.

**Example:**

```text
 0 [vc4hdmi        ]: vc4-hdmi - vc4-hdmi
                      vc4-hdmi
 1 [wm8960soundcard]: simple-card - wm8960-soundcard
                      wm8960-soundcard
```

### Check 5: Playback Devices

Check available playback (speaker/headphone) devices:

```bash
aplay -l
```

**Expected:** The WM8960 sound card listed with available playback devices. Shows card number, device number, and subdevices.

**Example:**

```text
card 1: wm8960soundcard [wm8960-soundcard], device 0: bcm2835-i2s-wm8960-hifi wm8960-hifi-0 [bcm2835-i2s-wm8960-hifi wm8960-hifi-0]
  Subdevices: 1/1
  Subdevice #0: subdevice #0
```

### Check 6: Recording Devices

Check available recording (microphone) devices:

```bash
arecord -l
```

**Expected:** The WM8960 sound card listed with available capture devices.

**Example:**

```text
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
- Log shows successful codec detection at I2C address `0x1a`
- Shows DKMS module status check
- Shows successful overlay loading and ALSA configuration
- Ends with all three health checks `[PASS]` and "WM8960 service initialization complete successfully"
- No error messages or warnings about missing devices

**Example log entries:**

```text
[2026-03-09 20:36:46] Starting WM8960 soundcard initialization (v1.3.0)...
[2026-03-09 20:36:48] DKMS module wm8960-soundcard/1.0 is installed for kernel 6.12.75+rpt-rpi-v8
[2026-03-09 20:36:48] Verifying I2C interface is available...
[2026-03-09 20:36:48] I2C interface verified
[2026-03-09 20:36:48] Loading i2c-dev kernel module...
[2026-03-09 20:36:53] Detecting WM8960 codec on I2C bus 1 at address 0x1a...
[2026-03-09 20:36:53] WM8960 codec detected on attempt 1
[2026-03-09 20:36:53] SUCCESS: WM8960 codec detected at I2C address 0x1a (value: 1a)
[2026-03-09 20:36:53] Loading wm8960-soundcard device tree overlay...
[2026-03-09 20:36:53] Device tree overlay loaded successfully
[2026-03-09 20:36:54] [PASS] Health check: WM8960 kernel module loaded
[2026-03-09 20:36:54] [PASS] Health check: WM8960 sound card visible to ALSA
[2026-03-09 20:36:54] [PASS] Health check: WM8960 playback devices available
[2026-03-09 20:36:54] WM8960 service initialization complete successfully
```

### Additional Check: DKMS Status

Verify the DKMS module is properly installed:

```bash
sudo dkms status
```

**Expected output:**
- Shows `wm8960-soundcard` module installed for your kernel version

**Example:**

```text
wm8960-soundcard/1.0, 6.12.75+rpt-rpi-v8, aarch64: installed
```

If all seven manual checks pass, your WM8960 Audio HAT is properly installed and ready to use.

---

## Uninstallation

```bash
cd ~/WM8960_AudioHAT_Drivers
sudo bash uninstall.sh
sudo reboot
```

The uninstallation script performs 11 steps:

1. Stop and disable the `wm8960-soundcard` systemd service
2. Stop and disable the ALSA auto-save timer
3. Remove systemd service files and utilities from `/etc/systemd/system/` and `/usr/bin/`
4. Remove ALSA WM8960 symlinks and restore previous config from backups
5. Remove PipeWire and PulseAudio configuration files (if present)
6. Remove the ALSA configuration directory (`/etc/wm8960-soundcard/`)
7. Remove the service log file and logrotate config
8. Remove the DKMS kernel module
9. Remove DKMS source files from `/usr/src/wm8960-soundcard-1.0/`
10. Remove the device tree overlay from `/boot/firmware/overlays/`
11. Clean up `# wm8960-managed` tagged lines from config.txt (with backup)

### Manual Cleanup (Optional)

Some system-level settings are preserved because they may be used by other software. If you want to completely remove everything:

```bash
# Pick the active config.txt path (Pi OS Trixie+ uses /boot/firmware/,
# older releases use /boot/)
[ -f /boot/firmware/config.txt ] && CONFIG=/boot/firmware/config.txt || CONFIG=/boot/config.txt

# Check if any wm8960-managed lines remain in config.txt
grep 'wm8960-managed' "$CONFIG"

# If present, remove them manually (dtparam=i2c_arm=on and dtoverlay=i2s-mmap)
sudo nano "$CONFIG"

# Remove i2c-dev from /etc/modules if not needed by other hardware
sudo nano /etc/modules

# Optionally remove packages (only if not needed by other software)
sudo apt-get remove --purge dkms i2c-tools libasound2-plugins
sudo apt-get autoremove
```

### Verify Removal

After rebooting, verify the removal:

```bash
sudo dkms status                                            # should not show wm8960-soundcard
cat /proc/asound/cards                                      # should not show wm8960soundcard
sudo systemctl status wm8960-soundcard.service              # should show "not found"
```

If you also installed the echo canceller, uninstall it separately:

```bash
cd ~/WM8960_AudioHAT_Drivers/tools/echo-cancel
sudo bash install.sh --uninstall
```
