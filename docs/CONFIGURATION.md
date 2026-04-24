# Configuration Reference

Detailed configuration reference for the WM8960 Audio HAT drivers, including config.txt settings, ALSA files, dynamic overlay loading, and advanced tuning.

## Contents
- [Required config.txt Settings](#required-configtxt-settings)
- [Configuration Files](#configuration-files)
- [Dynamic Loading Explanation](#dynamic-loading-explanation)
- [Advanced Configuration](#advanced-configuration)
- [Saving Audio Settings](#saving-audio-settings)
- [Service Management](#service-management)
- [Use Cases](#use-cases)

---

## Required config.txt Settings

The WM8960 driver requires specific settings in `/boot/firmware/config.txt` (or `/boot/config.txt` on older systems). The install script adds these automatically, but if you experience issues, verify these settings are present.

### Minimum Required Settings

Your config.txt must have the following in the `[all]` section (or at least not in a platform-specific section):

```text
# Required: Enable I2C interface for codec communication
dtparam=i2c_arm=on # wm8960-managed

# Enable I2S memory-mapped interface
dtoverlay=i2s-mmap # wm8960-managed
```

**Important notes:**
- `dtparam=i2c_arm=on` must only appear **once** in config.txt
- It must be in the `[all]` section to work on all Raspberry Pi models
- The installer tags lines it adds with `# wm8960-managed` so the uninstaller can safely remove them
- Multiple `dtparam` calls accumulate in the device tree overlay list, wasting memory and potentially causing driver failures

### Known Conflicts

**⚠️ `dtoverlay=i2s-mmap` Conflict:**

The install script adds `dtoverlay=i2s-mmap`, which is required for the I2S memory-mapped interface. However, if you have a custom audio setup it may conflict.

**Symptoms of conflict:**
- Silent failures during audio playback
- Unexpected audio routing behavior
- Service initialization failures related to I2S

**To resolve:**
```bash
sudo nano /boot/firmware/config.txt
# Comment out: # dtoverlay=i2s-mmap  # Disabled due to conflict
sudo reboot
```

### Example config.txt [all] Section

```text
[all]
# Enable I2C for WM8960 codec
dtparam=i2c_arm=on # wm8960-managed

# Enable I2S memory-mapped interface
dtoverlay=i2s-mmap # wm8960-managed

# Note: wm8960-soundcard overlay loaded dynamically by service for proper I2C detection # wm8960-managed
# Do NOT add: dtoverlay=wm8960-soundcard
```

### Verifying Your Configuration

```bash
# Check loaded overlays (should show wm8960-soundcard after service starts)
sudo dtoverlay -l

# Verify dtparam=i2c_arm appears only once
grep -c 'dtparam=i2c_arm' /boot/firmware/config.txt
# Expected: 1
```

---

## Configuration Files

### `/boot/firmware/config.txt`

> **Do NOT manually add** `dtoverlay=wm8960-soundcard` **to this file!**

The overlay is loaded dynamically by the service script, not statically in config.txt. This is intentional and crucial for proper operation. See [Dynamic Loading Explanation](#dynamic-loading-explanation) below.

If you previously added `dtoverlay=wm8960-soundcard`, remove it to prevent conflicts.

### `/etc/wm8960-soundcard/asound.conf`

The ALSA configuration file for the WM8960 sound card. It defines:
- **Default sound card:** Sets WM8960 as the default audio device
- **Playback settings:** Configures playback through the `dmix` plugin for software mixing
- **Mixer control:** Ensures ALSA mixer controls the correct hardware card

Symlinked to `/etc/asound.conf` by the initialization service. To customize audio settings, edit this file and restart the service.

### `/etc/wm8960-soundcard/wm8960_asound.state`

Stores the ALSA mixer state:
- Volume levels for playback and capture
- Mute/unmute states for various channels
- Routing configurations
- Hardware-specific control settings

Symlinked to `/var/lib/alsa/asound.state`. ALSA automatically restores these settings on boot.

To modify:
1. Use `alsamixer` to adjust settings
2. Save with `sudo alsactl store`

### `/etc/wm8960-soundcard/version`

Plain text file containing the installed driver version. Read by `wm8960-soundcard.sh`, `wm8960-volume`, and `wm8960-diag` for display. Written by the installer from the repo's `VERSION` file.

---

## Dynamic Loading Explanation

The WM8960 driver uses **dynamic overlay loading** via the systemd service instead of static loading in `/boot/firmware/config.txt`.

### Why Dynamic Loading?

**Problems with static loading:**
1. **Race conditions** — The overlay loads before the I2C bus is fully initialized, causing detection failures
2. **No detection logic** — Static loading doesn't verify the codec is present before attempting to load drivers
3. **Boot failures** — If hardware isn't connected, static overlays can cause boot problems or kernel warnings

**Benefits of dynamic loading:**
- **I2C detection** — Service verifies the codec is present on the I2C bus before loading drivers
- **Proper timing** — Allows time for the I2C bus and codec to be ready after boot
- **Graceful failure** — If hardware isn't connected, the system boots normally without errors
- **Configuration management** — Ensures ALSA configuration files are properly linked before audio initialization

### How It Works

1. **Service-based initialization:** `wm8960-soundcard.service` runs after `multi-user.target`, ensuring proper boot sequence. No network dependency.

2. **I2C detection:** The service script actively detects the codec on I2C bus 1 at address `0x1a` with up to 5 retry attempts with delays.

3. **No driver conflicts:** The driver uses the unique platform name `asoc-wm8960-soundcard`, avoiding conflicts with Pi's built-in audio drivers.

4. **Conditional loading:** The overlay is only loaded via `dtoverlay` if the codec is successfully detected.

5. **Symlink management:** After successful detection, the service creates proper symlinks for ALSA configuration files.

6. **Graceful failure:** If the codec isn't detected, the service exits with an error code, making it easy to diagnose.

---

## Advanced Configuration

### Adjusting Sample Rates

To change the default sample rate, modify `/etc/wm8960-soundcard/asound.conf`:

```bash
sudo nano /etc/wm8960-soundcard/asound.conf
```

Add rate conversion parameters to the PCM definition:

```text
pcm.!default {
    type plug
    slave {
        pcm "dmixer"
        rate 48000
    }
}
```

> **Note:** `dmixer` (and `dsnooper` for capture) are the PCM names already defined in the shipped `asound.conf`. Using `dmix` directly would reference ALSA's built-in dmix type, which isn't what the existing config wires up.

### Buffer Size Tuning

For Pi Zero models or audio-heavy loads, the default dmix buffer sizes can be tuned to reduce underruns. `asound.conf` includes commented-out hints:

```text
pcm.dmixer {
    type dmix
    ipc_key 555555
    slave {
        pcm "hw:wm8960soundcard"
        # Uncomment below to tune buffer sizes (may help with underruns on Pi Zero):
        # period_size 1024
        # buffer_size 4096
    }
}
```

### Custom Mixer Settings

Use `alsamixer` to adjust audio levels interactively:

```bash
alsamixer
```

Press **F6** to select the WM8960 sound card, then adjust:
- PCM playback volume
- Headphone volume
- Speaker volume
- Capture volume (microphone)
- Input source selection

Save with:
```bash
sudo alsactl store
```

For a full reference of every WM8960 ALSA control (useful for Wyoming/Rhasspy voice assistant setups), see [ALSA-Mixer-Controls.md](ALSA-Mixer-Controls.md).

### Volume Presets

The `wm8960-volume` utility provides tested, known-good mixer settings for common use cases:

```bash
sudo wm8960-volume <preset>
```

| Preset | Description |
|--------|-------------|
| `speakers` | Moderate speaker volume (0dB), headphones muted, Class D boost enabled |
| `headphones` | Comfortable headphone volume (-6dB), speakers muted, zero-cross enabled |
| `recording` | Mic capture with moderate gain, ALC off for clean manual control |
| `voice` | Optimized for voice assistants: ALC stereo + noise gate + high-pass filter |
| `max` | Maximum safe volume for all outputs (loud!) |
| `reset` | Restore factory defaults from the shipped state file |
| `show` | Display current output, input, and processing levels |

**Examples:**
```bash
sudo wm8960-volume speakers      # Set up for speaker playback
sudo wm8960-volume voice         # Optimize for voice assistants
sudo wm8960-volume show          # Check current levels
sudo wm8960-volume reset         # Restore factory defaults
```

**The `voice` preset** is specifically tuned for voice assistant and speech recognition use cases:
- Hardware ALC (Automatic Level Control) in stereo mode targeting -12dB
- Noise gate to cut silence noise
- ADC high-pass filter to remove DC offset and low-frequency rumble
- Speaker output at reduced volume to minimize echo feedback

After switching presets, save them with `sudo alsactl store` to persist across reboots.

---

## Saving Audio Settings

### Default Behavior: Manual Save

By default, ALSA mixer settings (volume, mute state, etc.) **do not persist** across reboots unless you manually save them. This follows standard ALSA practice and gives you full control.

**To save your audio settings:**

1. Configure with `alsamixer`:
   ```bash
   alsamixer
   ```

2. Save:
   ```bash
   sudo alsactl store
   ```

Settings now persist across reboots.

**Why manual save?**
- Prevents accidental changes from being saved
- Gives explicit control over your saved configuration
- Standard ALSA behavior that advanced users expect

### Optional: Automatic Saving

For consumer devices or convenience, enable automatic saving of ALSA mixer settings. When enabled, the auto-save timer will:
- Wait 30 minutes after boot (giving you time to configure settings)
- Save settings every 6 hours thereafter
- Automatically clean up old backup files (keeps last 5)

**Enable auto-save:**
```bash
sudo systemctl enable wm8960-alsa-store.timer
sudo systemctl start wm8960-alsa-store.timer
```

**Disable auto-save:**
```bash
sudo systemctl stop wm8960-alsa-store.timer
sudo systemctl disable wm8960-alsa-store.timer
```

**Check status:**
```bash
sudo systemctl status wm8960-alsa-store.timer
sudo journalctl -u wm8960-alsa-store.service -n 50
```

**Manually trigger a save:**
```bash
sudo systemctl start wm8960-alsa-store.service
```

### Backup Management

The system automatically manages backup files:

- **Boot-time cleanup:** Keeps last 10 backups (for manual save users)
- **Auto-save cleanup:** Keeps last 5 backups (for frequent save users)

Backups are stored in `/var/lib/alsa/` as `asound.state.backup.YYYYMMDD_HHMMSS`.

You can safely delete old backups manually:
```bash
# List all backups
ls -lh /var/lib/alsa/asound.state.backup.*

# Delete backups older than 30 days
find /var/lib/alsa/ -name "asound.state.backup.*" -mtime +30 -delete
```

---

## Service Management

**Enable service to start on boot** (enabled by default after install):
```bash
sudo systemctl enable wm8960-soundcard.service
```

**Disable service:**
```bash
sudo systemctl disable wm8960-soundcard.service
```

**Restart after configuration changes:**
```bash
sudo systemctl restart wm8960-soundcard.service
```

**View service status and recent output:**
```bash
sudo systemctl status wm8960-soundcard.service
sudo journalctl -u wm8960-soundcard.service -n 50
```

**View detailed service log** (timestamped, includes DKMS rebuild diagnostics):
```bash
sudo cat /var/log/wm8960-soundcard.log
```

---

## Use Cases

Once audio is working, here are some common projects and patterns people build with WM8960 HATs. These are starting points for inspiration — not features of this project.

### Voice Assistants

The highest-value use case for WM8960 HATs, especially with the ReSpeaker 2-Mic variant. Pair with the echo canceller for music/TTS that doesn't break wake-word detection.

```bash
# Install the echo canceller
cd tools/echo-cancel
sudo bash install.sh

# Point your voice assistant at the loopback devices:
#   playback:  hw:Loopback,0,0
#   capture:   hw:Loopback,1,1
```

Works with Home Assistant Wyoming satellites, Rhasspy, openWakeWord, Porcupine, and any Linux voice framework that accepts an ALSA device name. See [tools/echo-cancel/README.md](../tools/echo-cancel/README.md) and [ALSA-Mixer-Controls.md](ALSA-Mixer-Controls.md) for tuning guidance.

### Internet Radio

```bash
sudo apt install mpv
mpv "https://stream-url-here"

# Or with a playlist
mpv --shuffle playlist.m3u
```

For a headless auto-start on boot, wrap `mpv` in a systemd user service and point it at the WM8960 via `--audio-device=alsa/default`.

### Text-to-Speech

```bash
sudo apt install espeak-ng
espeak-ng "Hello, this is the WM8960 audio HAT speaking."

# Higher-quality TTS with piper (used by Home Assistant)
# See https://github.com/rhasspy/piper for install instructions
```

### Bluetooth Audio Streaming

Stream from your phone to the Pi's WM8960 using PipeWire's built-in Bluetooth support (Trixie default) or `bluealsa` for lighter headless setups:

```bash
# PipeWire (desktop / full image)
sudo apt install pipewire pipewire-pulse wireplumber libspa-0.2-bluetooth
systemctl --user restart pipewire

# bluealsa (headless, lighter)
sudo apt install bluealsa
sudo systemctl enable --now bluealsa
```

The installer already deploys a WirePlumber config making the WM8960 the default sink, so paired Bluetooth devices route here automatically.

### Audio Monitoring / Hardware Loopback

Pipe the mic straight to the speaker for live monitoring:

```bash
# Simple hardware monitor (any delay comes from ALSA buffers)
arecord -D default -f S16_LE -r 48000 -c 2 | aplay -D default

# Lower latency with smaller period/buffer
arecord -D default -f S16_LE -r 48000 -c 2 --period-size=256 --buffer-size=1024 \
    | aplay -D default --period-size=256 --buffer-size=1024
```

Note: this does NOT use echo cancellation — expect feedback if the mic and speaker are close together.

### Music Playback and DJ Use Cases

For music players that need specific ALSA devices:

```bash
# mpd (Music Player Daemon) — edit /etc/mpd.conf:
audio_output {
    type        "alsa"
    name        "WM8960"
    device      "plughw:wm8960soundcard,0"
}

# VLC — command line
cvlc --aout=alsa --alsa-audio-device=default music.mp3

# Spotify (spotifyd) — config.toml:
backend = "alsa"
device = "plughw:wm8960soundcard,0"
```

### Recording and Podcasting

```bash
# High-quality 48kHz stereo recording
arecord -D default -f S24_LE -r 48000 -c 2 -t wav podcast.wav

# Record with automatic gain control (hardware ALC)
sudo wm8960-volume recording
arecord -D default -f S16_LE -r 44100 -c 2 -t wav session.wav

# Record in chunks (useful for long sessions)
arecord -D default -f S16_LE -r 48000 -c 2 -t wav \
    --max-file-time=3600 \
    --use-strftime recordings/%Y/%m/%d-%H%M%S.wav
```

### Network Audio Streaming (AirPlay, etc.)

The installer configures PipeWire/PulseAudio defaults, so standard network audio tools work:

```bash
# AirPlay receiver
sudo apt install shairport-sync
# Uses PulseAudio/PipeWire defaults — WM8960 is already default

# Snapcast multi-room audio
sudo apt install snapclient snapserver
```

