# WM8960 ALSA Mixer Controls Reference for Wyoming & Rhasspy Satellite

This document provides a comprehensive overview of all WM8960 ALSA controls available on the current Raspberry Pi audio driver setup, with guidance and examples for usage in voice assistant frameworks like Wyoming and Rhasspy Satellite.

---
## General Guidelines
- Use `alsamixer` or `amixer` to view and change mixer settings.
- Many controls map directly to features exposed in Wyoming Satellite via volume/boost flags and can also help tune Rhasspy audio.
- ALSA mixer controls are accessible from CLI and Python (e.g., using `pyalsaaudio` or subprocess calls).

---
## Essential Audio Controls

### Playback
- **Playback Volume**: Main output volume for WM8960 DAC; adjust with `amixer sset 'Playback' N%` or Wyoming flag `--speaker-volume-multiplier`.
- **Headphone/Speaker Volume**: `Headphone`, `Speaker`. Used for fine-tuning output hardware levels.
- **PCM Playback -6dB**: Attenuates PCM output from ALSA for headroom. Typically left at default (off) unless distortion occurs.

### Capture / Microphone
- **Capture Volume**: Main ADC gain for recording/voice. Key for Wyoming `--mic-volume-multiplier` and Rhasspy input gain.
- **Capture Switch/ZC**: Enables/disables ADC capture and zero-crossing (for click-free changes).

### Microphone & Line Boost
- **Left/Right Input Boost Mixer LINPUT[1-3] / RINPUT[1-3]**: Analog boost for input channels. Use to increase mic sensitivity.
- **Left/Right Input Mixer Boost**: Overall input gain after analog mixing.

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
   amixer sset 'Capture' 80%   # Boost overall capture gain
   amixer sset 'Left Input Mixer Boost' on
   amixer sset 'Right Input Mixer Boost' on
   ```
   Or, use Wyoming flag:
   ```bash
   wyoming-satellite --mic-volume-multiplier 2.0
   ```
2. **Increase Speaker Output:**
   ```bash
   amixer sset 'Speaker' 100%
   wyoming-satellite --speaker-volume-multiplier 1.5
   ```
3. **Enable Live Monitoring / Loopback:**
   ```bash
   amixer sset 'Left Output Mixer Boost Bypass Switch' on
   amixer sset 'Right Output Mixer Boost Bypass Switch' on
   # Speak into the mic, hear yourself live in headphones/speaker
   ```
4. **Test All Controls (CLI):**
   ```bash
   alsamixer   # Full interactive mixer view
   amixer scontrols
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
- Wyoming Satellite: [Wyoming docs](https://github.com/OpenVoiceOS/wyoming-satellite)
- Rhasspy: [Rhasspy docs](https://rhasspy.readthedocs.io/en/latest/)

---
For further help with advanced use cases, reach out or open an issue in the repository.

---
