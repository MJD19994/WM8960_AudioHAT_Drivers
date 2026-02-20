# WM8960 Audio HAT Drivers - Development Roadmap

> **Goal:** Build the most robust, feature-complete WM8960 Audio HAT driver package for Raspberry Pi OS (Trixie+), supporting multiple HAT variants.

## Supported Hardware

| HAT | WM8960 | LEDs | Button | Status |
|-----|--------|------|--------|--------|
| Keyestudio Respeaker 2-Mic | Yes | 3x APA102 (SPI) | 1x GPIO | Primary test board |
| Generic WM8960 HATs (no LEDs) | Yes | No | No | Supported |
| Waveshare WM8960 Audio HAT | Yes | Power only (no control) | No | Planned |
| Seeed Respeaker 2-Mic v1.0 | Yes | 3x APA102 (SPI) | 1x GPIO | Planned |

---

## Phase 1: Audio Stack Integration (High Priority)

Core audio features that improve the user experience on desktop and headless setups.

### 1.1 PipeWire Configuration
- [ ] Detect if PipeWire is running (default on Trixie/Bookworm desktop)
- [ ] Ship WirePlumber rules to set WM8960 as default sink/source- [ ] Configure proper sample rate and buffer sizes
- [ ] Handle coexistence with HDMI audio (priority/profile switching)

### 1.2 PulseAudio Configuration
- [ ] Ship `default.pa` snippet for PulseAudio setups
- [ ] Set WM8960 as default sink/source
- [ ] Configure proper sample rate for voice and music use cases
- [ ] Install conditionally (only if PulseAudio is present)

### 1.3 Headphone Jack Detection
- [ ] Research WM8960 HP_L pin jack detect via ADDCTL1/ADDCTL2 registers
- [ ] Add GPIO jack detect properties to device tree overlay
- [ ] Verify `simple_util_init_hp()` in machine driver hooks up correctly
- [ ] Test automatic speaker mute when headphones inserted
- [ ] Update ALSA state to handle routing switch
- [ ] *Note: No manufacturer currently implements this - differentiator*

### 1.4 UCM (Use Case Manager) Profiles
- [ ] Create UCM profile for WM8960 sound card
- [ ] Define verb/device entries: Speaker, Headphones, Mic (Internal)
- [ ] Enable automatic output switching with jack detect (depends on 1.3)
- [ ] Install UCM files to `/usr/share/alsa/ucm2/`

---

## Phase 2: Extended Hardware Support (Medium Priority)

Support for hardware features beyond the WM8960 codec itself.

### 2.1 APA102 RGB LED Support (Respeaker 2-Mic HATs)
- [ ] Add SPI interface enable to install script (dtparam=spi=on)
- [ ] Ship Python utility script for LED control (APA102 over SPI)
- [ ] Provide LED patterns: boot indicator, recording active, volume level
- [ ] Install as optional component (skip on HATs without LEDs)
- [ ] Add `--with-leds` / `--without-leds` flag to install script
- [ ] Consider shipping a systemd service for boot LED indicator

### 2.2 GPIO User Button Support (Respeaker 2-Mic HATs)
- [ ] Identify GPIO pin used by Keyestudio Respeaker 2-Mic button
- [ ] Add `gpio-keys` device tree overlay or use `gpiod` userspace
- [ ] Ship example script: button triggers mute/unmute or recording
- [ ] Install as optional component (skip on HATs without button)

### 2.3 Device Tree Source (.dts)
- [ ] Decompile existing `.dtbo` to `.dts` on a Pi
- [ ] Clean up and comment the decompiled source
- [ ] Add `.dts` to repository alongside `.dtbo`
- [ ] Add `dtc` compilation step to install script (compile from source, fall back to prebuilt)
- [ ] Separate DTS variants if needed per HAT

---

## Phase 3: User Utilities (Lower Priority)

Quality-of-life scripts and tools.

### 3.1 Audio Test Script
- [x] `test-audio.sh` with 8 automated + interactive checks:
  - I2C codec detection at 0x1a
  - Kernel module verification (codec + soundcard)
  - Sound card visible in `/proc/asound/cards`
  - Playback device exists (`aplay -l`)
  - Capture device exists (`arecord -l`)
  - ALSA config symlink verification
  - Interactive speaker test with user confirmation
  - Interactive mic capture + playback test
  - `--quick` flag for non-interactive/CI use
  - Pass/fail/skip summary with exit code

### 3.2 Volume Preset Utility
- [x] `wm8960-volume` script with named presets:
  - `speakers` - moderate speaker volume, headphones muted, Class D boost
  - `headphones` - comfortable headphone volume (-6dB), speakers muted, zero-cross
  - `recording` - mic capture with moderate gain, ALC off for manual control
  - `voice` - voice assistant: ALC stereo + noise gate + HPF for speech (Phase 4.3 foundation)
  - `max` - maximum safe volume for all outputs
  - `reset` - restore factory defaults from shipped state file
  - `show` - display current mixer levels
- [x] Installed to `/usr/bin/wm8960-volume` via install.sh, removed via uninstall.sh

### 3.3 Softvol ALSA Plugin
- [ ] Add optional `softvol` plugin to `asound.conf` for smoother volume curves
- [ ] Make it configurable (some users prefer hardware-only volume control)

---

## Phase 4: Voice Assistant DSP & Audio Processing (High Priority)

Software DSP for voice assistant use cases. **No WM8960 HAT manufacturer ships any of this** --
SeeedStudio's DSP features only exist on their USB mic array (dedicated Conexant DSP chip).
The 2-Mic WM8960 HATs ship with zero audio processing, leaving users to figure it out.
This is the biggest differentiation opportunity for this project.

> **Key insight:** The most impactful DSP features can be delivered as **config files**, not custom
> code. PipeWire and PulseAudio already have processing engines built in -- they just need to be
> configured for the WM8960 hardware.

### Voice Assistant Audio Pipeline Reference

The typical preprocessing chain needed for wake word + STT:

```
Physical Mic (WM8960 ADC)
    |
[ALSA/PipeWire Capture] -- 16kHz, 16-bit, mono
    |
[High-Pass Filter] -- Remove <80Hz rumble, HVAC noise
    |
[Echo Cancellation] -- Remove speaker playback from mic signal (CRITICAL)
    |
[Noise Suppression] -- Remove steady-state background noise
    |
[AGC] -- Normalize to consistent mic level regardless of distance
    |
[VAD] -- Voice Activity Detection (reduces processing load)
    |
[Wake Word Engine] -- openwakeword, Porcupine, etc.
    |
[STT Engine] -- Whisper, Vosk, cloud STT
```

### Voice Assistant Format Requirements

All major voice assistants and wake word engines expect the same input:

| Engine | Format |
|--------|--------|
| Google Assistant SDK | 16kHz, 16-bit, mono PCM |
| Amazon AVS | 16kHz, 16-bit, mono, signed LE |
| Home Assistant / Wyoming | 16kHz, 16-bit, mono PCM |
| OpenWakeWord / Porcupine | 16kHz, 16-bit, mono |
| Whisper / Vosk | 16kHz, 16-bit or float32, mono |

The WM8960 natively supports 16kHz (no resampling needed), or 48kHz with software resample.

### 4.1 Echo Cancellation (Highest Value DSP Feature)

**Why this matters:** Without AEC, playing music or TTS through the speaker feeds back into the mic.
Wake word detection fails during playback, and STT accuracy drops dramatically. This is the #1
complaint from voice assistant users with audio HATs.

#### PipeWire AEC (for desktop / Trixie default)
- [ ] Ship drop-in config: `/etc/pipewire/pipewire.conf.d/wm8960-echo-cancel.conf`
- [ ] Use `libpipewire-module-echo-cancel` with WebRTC backend
- [ ] Configure: AEC + noise suppression + AGC in one module
- [ ] Set WM8960 playback as reference signal for cancellation
- [ ] Create virtual "processed" source that applications use
- [ ] Package dependency: `libspa-0.2-modules`, `pipewire-audio`

#### PulseAudio AEC (for older setups)
- [ ] Ship `default.pa` snippet loading `module-echo-cancel`
- [ ] Configure `aec_method=webrtc` with NS and AGC enabled
- [ ] Create virtual echo-cancelled source/sink pair
- [ ] Package dependency: `pulseaudio`

#### ALSA AEC (for headless / ALSA-only)
- [ ] Ship alternative `asound.conf` with SpeexDSP echo cancellation plugin
- [ ] Configure `type speex` PCM with echo reference device
- [ ] Lighter weight than WebRTC, runs on Pi Zero
- [ ] Package dependency: `libasound2-plugins`

### 4.2 Noise Suppression

#### RNNoise (Best Quality - Pi 3+ recommended, Zero 2W needs testing)
- [ ] Ship PipeWire filter-chain config with RNNoise module
- [ ] Neural network-based, significantly better than traditional NS
- [ ] Created by Jean-Marc Valin (Opus/Speex creator)
- [ ] Can be chained after AEC in PipeWire filter-chain
- [ ] Package dependency: `librnnoise-dev` (or build from source)
- [ ] Test on Pi Zero 2W to confirm performance is acceptable
- [ ] *Note: This would be a genuine differentiator -- no HAT driver ships this*

#### WebRTC NS (Good Quality - included with AEC)
- [ ] Enabled automatically as part of the AEC module config (4.1)
- [ ] No additional config needed when using PipeWire/PulseAudio AEC

#### SpeexDSP NS (Lightest - Pi Zero compatible)
- [ ] Enabled via `denoise=true` in ALSA speex plugin config
- [ ] Good for headless setups where PipeWire is not available

### 4.3 Automatic Gain Control (AGC)

- [ ] Software AGC via WebRTC (part of AEC config) for consistent mic levels
- [ ] Document recommended combination: mild hardware ALC + software AGC
- [ ] Ship ALSA state variant with ALC pre-configured for voice capture:
  - ALC Function: Stereo
  - ALC Target: -12dB (reasonable for speech)
  - ALC Max Gain: 5 (avoid excessive amplification)
  - Noise Gate: enabled with moderate threshold

### 4.4 Voice Assistant Setup Script

A helper script that configures the full DSP pipeline automatically.

- [ ] `wm8960-voice-assistant-setup` script that:
  1. Detects audio stack (PipeWire vs PulseAudio vs ALSA-only)
  2. Installs appropriate DSP config files for detected stack
  3. Installs required packages (`libspa-0.2-modules`, `libasound2-plugins`, etc.)
  4. Configures 16kHz capture path for voice applications
  5. Creates virtual "processed" mic device (echo-cancelled + noise-suppressed)
  6. Tests the pipeline with record-and-playback verification
  7. Provides connection instructions for Home Assistant / Wyoming / Google / Alexa

### 4.5 Voice Assistant Compatibility (Platform-Agnostic)

The DSP processing is delivered at the audio stack level so **any** voice assistant gets clean audio
automatically. No lock-in to a specific project.

- [ ] Document how to use the "processed" ALSA device with popular platforms:
  - Home Assistant (OHF-Voice / linux-voice-assistant)
  - Google Assistant SDK
  - Amazon AVS
  - Rhasspy / Wyoming protocol
  - Any application that reads from an ALSA capture device
- [ ] Ship example ALSA device names and arecord commands for integration guides
- [ ] Document expected audio format from processed device (16kHz, 16-bit, mono)
- [ ] LED integration: recording indicator on APA102 LEDs (for Respeaker HATs, Phase 2.1)

### 4.6 ALSA EQ & Audio Enhancement (Optional)

For music playback and general audio quality.

- [ ] Ship optional `alsaequal` config for 10-band parametric EQ
- [ ] Ship PipeWire filter-chain config for parametric EQ
- [ ] Document LADSPA plugin integration for advanced effects:
  - Compressor/limiter (normalize dynamic range)
  - High-pass filter (remove rumble)
  - Reverb (for music playback)
- [ ] Package dependencies: `libasound2-plugin-equal`, `swh-plugins`

### DSP Compatibility Matrix

| Feature | Best Tool | Pi Zero 2W | Pi 3+ | Pi 4/5 | Delivered As |
|---------|-----------|------------|-------|--------|--------------|
| Echo Cancellation | WebRTC | Yes | Yes | Yes | Config file |
| Noise Suppression | WebRTC NS / RNNoise | WebRTC NS | RNNoise | RNNoise | Config file |
| AGC | WebRTC | Yes | Yes | Yes | Config file |
| Parametric EQ | PipeWire / alsaequal | alsaequal | Both | Both | Config file |
| VAD | webrtcvad | Yes | Yes | Yes | Python pkg |
| Wake Word | openwakeword | Needs testing | Yes | Yes | Python pkg |

---

## Phase 5: Build System & Maintainability

Long-term project health.

### 5.1 Multi-Kernel Overlay Compilation
- [ ] Compile DTS at install time using `dtc` for the running kernel
- [ ] Fall back to precompiled `.dtbo` if `dtc` is not available
- [ ] Test across kernel 6.1, 6.6, 6.12+ (Bookworm, Trixie)

### 5.2 Mainline Codec Driver Option
- [ ] Test with kernel's built-in `snd-soc-wm8960` (no custom codec)
- [ ] If viable, offer `--use-mainline-codec` install flag
- [ ] Would eliminate DKMS dependency for users who prefer it
- [ ] Document trade-offs (mainline may have PLL issues on Pi)

### 5.3 HAT Auto-Detection
- [ ] Detect which HAT variant is connected at install/boot time
- [ ] Use I2C scan + SPI probe + GPIO check to identify board
- [ ] Automatically enable/disable LED and button support
- [ ] Store detected HAT type in `/etc/wm8960-soundcard/hat-type`

### 5.4 CI/CD
- [ ] GitHub Actions workflow for:
  - Shell script linting (shellcheck)
  - Kernel module compilation test (cross-compile)
  - DTS compilation verification
- [ ] Automated release tagging with changelog

---

## Completed Features

Features already implemented and working.

- [x] Custom WM8960 codec driver (`snd-soc-wm8960.ko`)
- [x] Custom machine driver (`snd-soc-wm8960-soundcard.ko`)
- [x] DKMS module management
- [x] Dynamic overlay loading via systemd service
- [x] I2C codec detection with 5 retries
- [x] Overlay double-load prevention
- [x] ALSA dmix/dsnoop/asym/plug configuration
- [x] ALSA state save/restore
- [x] ALSA auto-save timer (optional, 6h interval)
- [x] Backup rotation (10 boot / 5 periodic)
- [x] 3 post-init health checks
- [x] Debug mode (DEBUG=1)
- [x] Timestamped logging to `/var/log/wm8960-soundcard.log`
- [x] 13-step install with progress reporting
- [x] 5-point install validation
- [x] Boot partition auto-detection (`/boot/firmware/` vs `/boot/`)
- [x] Config.txt backup before modifications
- [x] I2S-MMAP conflict detection
- [x] Systemd retry logic (3 retries, 120s timeout)
- [x] Clean uninstall script (10 steps)
- [x] Kernel 6.13+ compatibility wrappers
- [x] Unique driver naming (`asoc-wm8960-soundcard`) to avoid conflicts
- [x] Comprehensive README and TROUBLESHOOTING docs
- [x] All WM8960 hardware DSP controls exposed (3D enhance, ALC, noise gate, HPF, deemphasis)

---

## Priority Legend

| Phase | Impact | Effort | When |
|-------|--------|--------|------|
| Phase 1 | High - core audio UX | Medium | Next |
| Phase 2 | Medium - hardware extras | Medium-High | After Phase 1 |
| Phase 3 | Lower - quality of life | Low-Medium | Ongoing |
| Phase 4 | High - voice assistant DSP | Medium | Alongside Phase 1 |
| Phase 5 | Maintainability | High | Ongoing |
