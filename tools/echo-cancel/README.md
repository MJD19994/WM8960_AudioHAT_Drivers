# WM8960 Echo Canceller (Bare ALSA)

Acoustic echo cancellation for the WM8960 Audio HAT on Raspberry Pi without PipeWire or PulseAudio. Two engines available:

| Engine | Attenuation | Double-talk | Requirements | Best for |
|--------|-------------|-------------|-------------|----------|
| **WebRTC AEC3** (default) | ~30dB+ | Excellent | snd-aloop module | Voice assistants, conferencing |
| **SpeexDSP** | ~15dB | Fair | None | Wake-word detection, simple setups |

For PipeWire or PulseAudio users, drop-in configs are also provided in [`configs/`](configs/).

## Install

```bash
cd tools/echo-cancel

# WebRTC AEC3 (recommended — best quality)
sudo bash install.sh

# Or SpeexDSP (simpler, no snd-aloop needed)
sudo bash install.sh speex
```

The installer handles all dependencies, builds from source, installs the binary, and creates a systemd service. On Raspberry Pi OS, `snd-aloop` is typically available as a built-in kernel module — the installer tries `modprobe snd-aloop` first and only builds via DKMS if that fails.

## How It Works

### WebRTC AEC3 (default)

The EC binary acts as the audio router between applications and hardware:

```text
App plays to hw:Loopback,0,0
  → (snd-aloop) → EC reads from hw:Loopback,1,0
  → EC feeds reference to WebRTC AEC3
  → EC writes to WM8960 speaker (plughw:wm8960soundcard,0)
  → EC reads from WM8960 mic (dsnooper)
  → WebRTC AEC3 removes echo
  → EC writes to hw:Loopback,0,1
  → (snd-aloop) → App records from hw:Loopback,1,1 (clean audio)
```

No FIFOs in the audio path. Single-threaded loop ensures the reference signal is perfectly aligned with the microphone capture.

### SpeexDSP (legacy)

Based on [voice-engine/ec](https://github.com/voice-engine/ec). Uses named pipes (`/tmp/ec.input`, `/tmp/ec.output`) for audio I/O with SpeexDSP for echo cancellation.

## Usage

### WebRTC

> **Important:** When the WebRTC echo canceller is running, it has exclusive access to the WM8960 speaker. All audio playback and recording **must** go through the loopback devices, not `default` or `hw:wm8960soundcard`.

```bash
# Play audio (goes through EC → speaker)
aplay -D hw:Loopback,0,0 music.wav

# Record echo-cancelled audio
arecord -D hw:Loopback,1,1 -r 48000 -c 1 -f S16_LE -d 5 recording.wav

# Play back a recording (also through loopback)
aplay -D hw:Loopback,0,0 recording.wav
```

Configure your voice assistant to use:
- **Playback device:** `hw:Loopback,0,0`
- **Capture device:** `hw:Loopback,1,1`

> **Note:** The `aec` virtual ALSA device defined in `configs/alsa-aec.conf` is **not compatible** with the default WebRTC service. The default service runs the EC binary in raw loopback-router mode (it writes directly to the speaker via `-p plughw:wm8960soundcard,0`), while the `aec` device routes playback to both the speaker AND the loopback simultaneously — using `aplay -D aec` would cause duplicate playback. The `aec` device is provided for advanced users running the EC binary in a different mode (without the `-p` flag). Stick to `hw:Loopback,0,0` / `hw:Loopback,1,1` unless you know what you're doing.

### SpeexDSP

```bash
# Record echo-cancelled audio
timeout 5 sox -t raw -r 48000 -c 1 -b 16 -e signed /tmp/ec.output -t wav recording.wav

# Play audio through the echo canceller (raw 48kHz mono S16_LE)
sox input.wav -r 48000 -c 1 -b 16 -e signed -t raw - > /tmp/ec.input
```

### WebRTC Tuning Flags

```text
-r rate   Sample rate: 16000, 32000, or 48000 (default: 48000)
-n level  Noise suppression: 0=off 1=low 2=mod 3=high 4=vhigh (default: 1)
-g        Enable automatic gain control
-M        Mobile mode (AECM — lighter CPU, less cancellation)
-H        Disable high-pass filter
-d ms     Stream delay hint in ms (default: 0)
-s        Save debug audio to /tmp/{recording,playback,out}.raw
-D        Daemonize
```

### SpeexDSP Tuning Flags

```text
-i PCM            Capture PCM device (default: default)
-o PCM            Playback PCM device (default: default)
-r rate           Sample rate (default: 16000)
-c channels       Recording channels (default: 2)
-b size           Ring buffer size in bytes (default: 262144)
-d delay          System delay between playback and capture in frames (default: 0)
-f filter_length  AEC filter length in samples (default: 2048)
-s                Save debug audio to /tmp/{recording,playback,out}.raw
-D                Daemonize
```

Audio I/O is through named pipes: `/tmp/ec.input` (playback) and `/tmp/ec.output` (recording). Only mono playback is supported.

### Service Management

```bash
systemctl status wm8960-echo-cancel
systemctl restart wm8960-echo-cancel
journalctl -u wm8960-echo-cancel -f
```

## Testing

> **Do NOT test with pure sine waves.** WebRTC AEC3 has a transparent mode that detects narrow-band signals and disables suppression — pure tones will show 0dB attenuation. This is by design, not a bug. Always test with broadband noise or real speech.

```bash
# Generate broadband noise for testing
sox -n -r 48000 -c 1 -b 16 noise.wav synth 10 pinknoise

# Play noise through EC while recording
aplay -D hw:Loopback,0,0 noise.wav &
arecord -D hw:Loopback,1,1 -r 48000 -c 1 -f S16_LE -d 10 recording.wav

# Compare levels — recording should be ~30dB quieter than noise.wav
sox noise.wav -n stat 2>&1 | grep "Maximum amplitude"
sox recording.wav -n stat 2>&1 | grep "Maximum amplitude"
```

## PipeWire / PulseAudio

Drop-in echo cancellation configs are provided in `configs/`:

- **PipeWire:** `configs/pipewire-echo-cancel.conf`
  ```bash
  sudo mkdir -p /etc/pipewire/pipewire.conf.d
  sudo cp configs/pipewire-echo-cancel.conf /etc/pipewire/pipewire.conf.d/20-echo-cancel.conf
  systemctl --user restart pipewire
  ```

- **PulseAudio:** `configs/pulse-echo-cancel.pa`
  ```bash
  sudo mkdir -p /etc/pulse/default.pa.d
  sudo cp configs/pulse-echo-cancel.pa /etc/pulse/default.pa.d/echo-cancel.pa
  pulseaudio -k
  ```

These use PipeWire/PulseAudio's built-in WebRTC AEC modules and do NOT require snd-aloop or the EC binary — they work independently of the bare-ALSA approach.

**Note:** The device names in these configs assume standard Raspberry Pi OS ALSA naming. Verify with `pw-cli list-objects Node | grep node.name` (PipeWire) or `pactl list sinks short` (PulseAudio) and update if needed.

## Limitations

- **WebRTC AEC3 performs best with broadband signals** (speech, music, noise). Pure tones (beeps, single-frequency alerts) may not be fully cancelled due to AEC3's transparent mode detection.
- **WebRTC requires snd-aloop** kernel module. On RPi OS, this is usually available via `modprobe`; if not, it's built via DKMS automatically.
- **WebRTC takes exclusive access** to the WM8960 speaker while running. All playback must go through the loopback device.
- **SpeexDSP provides ~15dB attenuation** — adequate for wake-word detection but noticeable echo remains.
- **SpeexDSP may attenuate speech** along with echo during simultaneous playback.

## Uninstall

```bash
sudo bash install.sh --uninstall
```

## License

The echo-cancel tools are licensed GPL-3.0-or-later; see [../../docs/LICENSING.md](../../docs/LICENSING.md) and [LICENSE-GPL3](LICENSE-GPL3) for the authoritative per-component breakdown. The SpeexDSP engine is based on [voice-engine/ec](https://github.com/voice-engine/ec).

The PortAudio ring buffer (`pa_ringbuffer.c`, `pa_ringbuffer.h`, `pa_memorybarrier.h`) is vendored from [PortAudio](http://www.portaudio.com) under a BSD-style license — see the file headers for details.
