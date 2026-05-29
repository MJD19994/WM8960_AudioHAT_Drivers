# WM8960 ALSA Mixer Controls Reference for Wyoming & Rhasspy Satellite

This document provides a comprehensive overview of all WM8960 ALSA controls available on the current Raspberry Pi audio driver setup, with guidance and examples for usage in voice assistant frameworks like Wyoming and Rhasspy Satellite.

---

## General Guidelines
- Use `alsamixer` or `amixer` to view and change mixer settings.
- Many controls map directly to features exposed in Wyoming Satellite via volume/boost flags and can also help tune Rhasspy audio.
- ALSA mixer controls are accessible from CLI and Python (e.g., using `pyalsaaudio` or subprocess calls).

---

## Inspecting Controls with `amixer`

```bash
# List every control on the WM8960 card
amixer -c wm8960soundcard scontrols

# Show everything (controls + current values) — verbose but complete
amixer -c wm8960soundcard

# Read a single control
amixer -c wm8960soundcard sget 'Playback Volume'
amixer -c wm8960soundcard sget 'Capture Volume'

# Short summary of all card information (capabilities, rates, formats)
amixer -c wm8960soundcard info
```

**Tip:** Always pass `-c wm8960soundcard` (or `-c <card-index>`) to `amixer`. Without it, `amixer` operates on the default card, which may not be the WM8960 if you have multiple audio devices.

## Setting Controls

```bash
# Set a volume by percentage
amixer -c wm8960soundcard sset 'Playback Volume' 80%
amixer -c wm8960soundcard sset 'Speaker Playback Volume' 100%
amixer -c wm8960soundcard sset 'Headphone Playback Volume' 75%
amixer -c wm8960soundcard sset 'Capture Volume' 60%

# Set by absolute value (check range with sget first)
amixer -c wm8960soundcard sset 'Playback Volume' 200

# Set in dB (prefix with 'dB')
amixer -c wm8960soundcard sset 'Playback Volume' -6.0dB

# Relative adjustments
amixer -c wm8960soundcard sset 'Playback Volume' 5%+   # up 5%
amixer -c wm8960soundcard sset 'Playback Volume' 5%-   # down 5%

# Switch-type controls (on/off)
amixer -c wm8960soundcard sset 'Left Input Mixer Boost Switch' on
amixer -c wm8960soundcard sset 'Noise Gate Switch' on
amixer -c wm8960soundcard sset 'ADC High Pass Filter Switch' on

# Zero-crossing volume transitions (click-free volume changes — NOT a mute)
amixer -c wm8960soundcard sset 'Speaker Playback ZC Switch' on
amixer -c wm8960soundcard sset 'Headphone Playback ZC Switch' on

# Effectively mute output (the WM8960 driver doesn't expose a plain
# "Playback Switch" — set volume to 0 instead, or use alsamixer's M key)
amixer -c wm8960soundcard sset 'Speaker Playback Volume' 0%
amixer -c wm8960soundcard sset 'Headphone Playback Volume' 0%

# Enum-type controls
amixer -c wm8960soundcard sset 'ALC Function' Stereo
amixer -c wm8960soundcard sset 'ALC Mode' Limiter
```

## Saving and Restoring Mixer State

```bash
# Save current state to default location
sudo alsactl store

# Save to a specific file
sudo alsactl store -f ~/my-wm8960-settings.state wm8960soundcard

# Restore from default location (happens automatically at boot via the service)
sudo alsactl restore

# Restore from a specific file
sudo alsactl restore -f ~/my-wm8960-settings.state

# Reset to shipped factory defaults
sudo wm8960-volume reset
```

## Scripting Mixer Changes

Common patterns when wrapping these in a script:

```bash
# Check if a control exists before setting it (avoids errors on unsupported cards)
if amixer -c wm8960soundcard sget 'Noise Gate Switch' >/dev/null 2>&1; then
    amixer -c wm8960soundcard sset 'Noise Gate Switch' on
fi

# Get just the percentage value of a control (useful for status bars)
amixer -c wm8960soundcard sget 'Playback Volume' | grep -oE '[0-9]+%' | head -1

# Capture whether a switch is on or off
state=$(amixer -c wm8960soundcard sget 'Noise Gate Switch' | grep -oE '\[on\]|\[off\]' | head -1)
```

---

## Essential Audio Controls

### Playback
- **Playback Volume**: Main output volume for WM8960 DAC; adjust with `amixer sset 'Playback Volume' N%` or Wyoming flag `--speaker-volume-multiplier`.
- **Headphone/Speaker Volume**: `Headphone Playback Volume`, `Speaker Playback Volume`. Used for fine-tuning output hardware levels.
- **PCM Playback -6dB**: Attenuates PCM output from ALSA for headroom. Typically left at default (off) unless distortion occurs.

### Capture / Microphone
- **Capture Volume**: Main ADC gain for recording/voice. Key for Wyoming `--mic-volume-multiplier` and Rhasspy input gain.
- **Capture Switch/ZC**: Enables/disables ADC capture and zero-crossing (for click-free changes).

### Microphone & Line Boost
- **Left/Right Input Boost Mixer LINPUT[1-3] / RINPUT[1-3]**: Analog boost for input channels. Use to increase mic sensitivity.
- **Left/Right Input Mixer Boost Switch**: Enables boost from input PGA to ADC. Use `amixer sset 'Left Input Mixer Boost Switch' on`.

---

## Advanced Controls

### Loopback / Monitoring
- **Left/Right Output Mixer Boost Bypass**: Enable to send analog input directly to output (headphone/speaker) for live monitoring / loopback.
  - Example: `amixer sset 'Left Output Mixer Boost Bypass Switch' on`
  - In Wyoming: Enable loopback via custom startup script if desired for voice feedback.

### Input/Output Routing
- **Input/Output Mixers** (LINPUT3, RINPUT3, PCM switches): Flexibly route input sources to outputs/playback.
- **Speaker Output Mixer, Headphone Output Mixer**: Fine control over hardware routing.

### Automatic Level Control (ALC)
- **ALC Function, Mode, Max/Min Gain, Attack, Decay, Hold Time, Target**: Digital auto-gain/limiter; can help normalize incoming speech volume especially in noisy environments.
  - Example: `amixer sset 'ALC Mode' Limiter`

### Noise Gate & Filters
- **Noise Gate, Threshold**: Filters out low-level background noise during capture.
- **ADC/DAC High Pass Filter, Polarity, Mono Mix, Deemphasis**: Digital processing options for advanced tuning and experiments.
- **3D Controls**: Experimental stereo effects; rarely used in voice apps.

---

## Example Usage in Wyoming Satellite

1. **Boost Mic Volume via Control:**
   ```bash
   amixer -c wm8960soundcard sset 'Capture Volume' 80%   # Boost overall capture gain
   amixer -c wm8960soundcard sset 'Left Input Mixer Boost Switch' on
   amixer -c wm8960soundcard sset 'Right Input Mixer Boost Switch' on
   ```
   Or, use Wyoming flag:
   ```bash
   wyoming-satellite --mic-volume-multiplier 2.0
   ```
2. **Increase Speaker Output:**
   ```bash
   amixer -c wm8960soundcard sset 'Speaker Playback Volume' 100%
   wyoming-satellite --speaker-volume-multiplier 1.5
   ```
3. **Enable Live Monitoring / Loopback:**
   ```bash
   amixer -c wm8960soundcard sset 'Left Output Mixer Boost Bypass Switch' on
   amixer -c wm8960soundcard sset 'Right Output Mixer Boost Bypass Switch' on
   # Speak into the mic, hear yourself live in headphones/speaker
   ```
4. **Test All Controls (CLI):**
   ```bash
   alsamixer   # Full interactive mixer view
   amixer -c wm8960soundcard scontrols
   ```

---

## Tuning for Rhasspy Satellite
- Use `alsamixer` to boost mic inputs and experiment with ALC/Noise Gate if inputs are too quiet or noisy.
- Fine-tune Capture/Playback/Speaker volumes for best wakeword and STT accuracy.
- Rhasspy reads default ALSA config. No extra steps required unless using multiple sound cards.

---

## Troubleshooting
- If audio is unexpectedly low/noisy: Try boosting input mixers and enabling ALC / Noise Gate.
- If monitoring isn't working: Check that loopback/bypass switches are enabled and outputs not muted/misdirected.
- Always run `alsactl store` after tuning to save settings.

---

## References
- Hardware: WM8960 Codec (Seeed, Keyestudio, Waveshare, SparkFun)
- ALSA: [Official docs](https://alsa-project.org/wiki/Main_Page), [amixer doc](https://linux.die.net/man/1/amixer)
- Wyoming Satellite: [Wyoming docs](https://github.com/rhasspy/wyoming-satellite) (archived Jan 2026; successor: [Linux Voice Assistant](https://github.com/OHF-Voice/linux-voice-assistant))
- Rhasspy: [Rhasspy docs](https://rhasspy.readthedocs.io/en/latest/)

---
For further help with advanced use cases, reach out or open an issue in the repository.

---
