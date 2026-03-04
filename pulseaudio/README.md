# PulseAudio Configuration Guide for WM8960 Audio HAT

This guide covers setting up PulseAudio to use the WM8960 Audio HAT as the default audio device on Raspberry Pi.

> **Note:** Raspberry Pi OS Trixie (and newer) uses PipeWire by default. If you're on Trixie desktop, see the [PipeWire guide](../pipewire/README.md) instead. This guide is for systems running native PulseAudio (Bookworm desktop or custom setups).

## Automatic Setup (Recommended)

If PulseAudio is already installed when you run the install script, configuration is handled automatically:

```bash
sudo bash install.sh
```

The installer detects native PulseAudio and deploys the default device config. No manual steps needed.

> **Important:** If `pipewire-pulse` is installed (PipeWire's PulseAudio compatibility layer), the installer skips PulseAudio configuration and uses WirePlumber rules instead. This is the correct behavior.

## Manual Setup

Use this if you installed the WM8960 driver first and added PulseAudio afterward, or if you need to reconfigure.

### Prerequisites

Install PulseAudio:

```bash
sudo apt install pulseaudio
```

### Install the PulseAudio Configuration

Copy the config snippet to PulseAudio's drop-in directory:

```bash
sudo mkdir -p /etc/pulse/default.pa.d
sudo cp pulseaudio/pulseaudio-wm8960.pa /etc/pulse/default.pa.d/wm8960-default.pa
```

Restart PulseAudio to apply:

```bash
pulseaudio -k
pulseaudio --start
```

Or reboot:

```bash
sudo reboot
```

### Verify Configuration

Check that WM8960 is set as the default sink and source:

```bash
pactl info
```

Expected output (look for the Default Sink/Source lines):

```
Server String: /run/user/1000/pulse/native
Default Sink: alsa_output.platform-wm8960-soundcard.analog-stereo
Default Source: alsa_input.platform-wm8960-soundcard.analog-stereo
```

List all available sinks and sources:

```bash
# List output devices
pactl list sinks short

# List input devices
pactl list sources short
```

### Switching Between Devices

To temporarily switch to HDMI output:

```bash
# List available sinks to find the HDMI sink name
pactl list sinks short

# Set HDMI as default
pactl set-default-sink alsa_output.platform-vc4-hdmi.hdmi-stereo
```

To switch back to WM8960:

```bash
pactl set-default-sink alsa_output.platform-wm8960-soundcard.analog-stereo
```

## How It Works

The configuration file (`pulseaudio-wm8960.pa`) is placed in PulseAudio's drop-in directory (`/etc/pulse/default.pa.d/`). PulseAudio executes files in this directory after loading `default.pa`, allowing us to override the default sink and source without modifying system files.

The two commands in the config:

```
set-default-sink alsa_output.platform-wm8960-soundcard.analog-stereo
set-default-source alsa_input.platform-wm8960-soundcard.analog-stereo
```

PulseAudio uses stable device names based on the ALSA card's platform identifier, so these names persist across reboots.

## Troubleshooting

### Default Sink/Source Not Set Correctly

1. Check if the config file is in place:
   ```bash
   ls -la /etc/pulse/default.pa.d/wm8960-default.pa
   ```

2. Verify the actual sink/source names PulseAudio sees:
   ```bash
   pactl list sinks | grep -E "Name:|Description:"
   pactl list sources | grep -E "Name:|Description:"
   ```
   If the names don't match `alsa_output.platform-wm8960-soundcard.analog-stereo`, update the config file with the correct names.

3. Check if `module-stream-restore` is overriding defaults (it remembers per-app device choices):
   ```bash
   # Temporarily disable stream restore to test
   pactl unload-module module-stream-restore
   pactl set-default-sink alsa_output.platform-wm8960-soundcard.analog-stereo
   ```

### PulseAudio Not Detecting the Sound Card

Make sure the WM8960 ALSA driver is loaded first:

```bash
cat /proc/asound/cards
```

You should see `wm8960soundcard` listed. If not, check:

```bash
sudo systemctl status wm8960-soundcard.service
sudo cat /var/log/wm8960-soundcard.log
```

### PulseAudio Not Starting

Check the PulseAudio log:

```bash
journalctl --user -u pulseaudio
```

Or start manually with verbose output:

```bash
pulseaudio -k
pulseaudio -vvv
```

### Conflict with PipeWire

If you see `pipewire-pulse` in `dpkg -l | grep pulse`, PipeWire is providing PulseAudio compatibility. In this case:

- The `pactl` commands still work (they talk to PipeWire's PulseAudio layer)
- But device defaults are controlled by WirePlumber, not PulseAudio config files
- See the [PipeWire guide](../pipewire/README.md) for the correct configuration

## Removing Configuration

To remove the PulseAudio config:

```bash
sudo rm /etc/pulse/default.pa.d/wm8960-default.pa
pulseaudio -k && pulseaudio --start
```

Or run the uninstall script which handles this automatically:

```bash
sudo bash uninstall.sh
```
