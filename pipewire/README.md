# PipeWire Configuration Guide for WM8960 Audio HAT

This guide covers setting up PipeWire/WirePlumber to use the WM8960 Audio HAT as the default audio device on Raspberry Pi.

## Automatic Setup (Recommended)

If PipeWire/WirePlumber is already installed when you run the install script, configuration is handled automatically:

```bash
sudo bash install.sh
```

The installer detects WirePlumber and deploys the priority rules. No manual steps needed.

## Manual Setup

Use this if you installed the WM8960 driver first and added PipeWire afterward, or if you need to reconfigure.

### Prerequisites

Install PipeWire and WirePlumber:

```bash
sudo apt install pipewire pipewire-pulse wireplumber
```

> **Note:** `pipewire-pulse` replaces PulseAudio with PipeWire's compatibility layer. If you have native PulseAudio installed, it will be removed. This is the recommended setup for Raspberry Pi OS Trixie.

### Install the WirePlumber Configuration

Copy the WirePlumber rules to the system config directory:

```bash
sudo mkdir -p /etc/wireplumber/wireplumber.conf.d
sudo cp pipewire/wireplumber-wm8960.conf /etc/wireplumber/wireplumber.conf.d/40-wm8960-default.conf
```

Restart WirePlumber to apply:

```bash
systemctl --user restart wireplumber
```

Or reboot:

```bash
sudo reboot
```

### Verify Configuration

Check that WM8960 is set as the default device (marked with `*`):

```bash
wpctl status
```

Expected output (look for the asterisk):

```
Audio
 ├─ Sinks:
 │      *  WM8960 Audio HAT (Speaker/Headphone) [vol: 0.74]
 │         vc4-hdmi
 │
 ├─ Sources:
 │      *  WM8960 Audio HAT (Microphone) [vol: 0.74]
```

You can also check with:

```bash
# List all audio devices
pw-cli list-objects Node

# Check default sink
wpctl inspect @DEFAULT_AUDIO_SINK@

# Check default source
wpctl inspect @DEFAULT_AUDIO_SOURCE@
```

### Switching Between Devices

To temporarily switch to HDMI output:

```bash
# Find the HDMI node ID from wpctl status
wpctl set-default <hdmi-node-id>
```

To switch back to WM8960:

```bash
wpctl set-default <wm8960-node-id>
```

The WM8960 will be restored as default on next boot (the priority rules ensure this).

## How It Works

The configuration file (`wireplumber-wm8960.conf`) uses WirePlumber's ALSA monitor rules to match the WM8960 audio nodes and boost their session priority above HDMI:

- **WM8960 priority:** 1500 (sink and source)
- **HDMI default priority:** ~1000

WirePlumber automatically selects the highest-priority device as the default. The rules match on `alsa.card_name = "wm8960-soundcard"` and `media.class` (Audio/Sink or Audio/Source), which are stable identifiers regardless of the platform device path.

## Troubleshooting

### WM8960 Not Showing as Default

1. Verify WirePlumber is running:
   ```bash
   systemctl --user status wireplumber
   ```

2. Check if the config file is in place:
   ```bash
   ls -la /etc/wireplumber/wireplumber.conf.d/40-wm8960-default.conf
   ```

3. Check the actual node names PipeWire sees:
   ```bash
   pw-cli list-objects Node | grep -E "node.name|node.description"
   ```
   Look for nodes with `alsa.card_name = "wm8960-soundcard"` in the output.

### PipeWire Not Detecting the Sound Card

Make sure the WM8960 ALSA driver is loaded first:

```bash
cat /proc/asound/cards
```

You should see `wm8960soundcard` listed. If not, check:

```bash
sudo systemctl status wm8960-soundcard.service
sudo cat /var/log/wm8960-soundcard.log
```

### Audio Crackling or Dropouts

Try adjusting the buffer size in PipeWire. Create or edit `/etc/pipewire/pipewire.conf.d/wm8960-latency.conf`:

```
context.properties = {
    default.clock.rate          = 48000
    default.clock.quantum       = 1024
    default.clock.min-quantum   = 512
}
```

Restart PipeWire: `systemctl --user restart pipewire`

## Removing Configuration

To remove the WirePlumber rules:

```bash
sudo rm /etc/wireplumber/wireplumber.conf.d/40-wm8960-default.conf
systemctl --user restart wireplumber
```

Or run the uninstall script which handles this automatically:

```bash
sudo bash uninstall.sh
```
