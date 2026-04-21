# WM8960 Audio HAT Drivers for Raspberry Pi

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/MJD19994/WM8960_AudioHAT_Drivers)](https://github.com/MJD19994/WM8960_AudioHAT_Drivers/releases)
[![CI](https://github.com/MJD19994/WM8960_AudioHAT_Drivers/actions/workflows/ci.yml/badge.svg)](https://github.com/MJD19994/WM8960_AudioHAT_Drivers/actions/workflows/ci.yml)
![Raspberry Pi OS](https://img.shields.io/badge/Raspberry%20Pi%20OS-Trixie-success?style=flat-square)
![Kernel 6.12](https://img.shields.io/badge/kernel-6.12%20validated-2ea44f?style=flat-square)
![DKMS](https://img.shields.io/badge/DKMS-supported-yellow?style=flat-square)
![ALSA](https://img.shields.io/badge/ALSA-integrated-blue?style=flat-square)
![PulseAudio](https://img.shields.io/badge/PulseAudio-supported-blue?style=flat-square)
![PipeWire](https://img.shields.io/badge/PipeWire-supported-blue?style=flat-square)
![ReSpeaker](https://img.shields.io/badge/ReSpeaker%202--Mic-compatible-1f6feb?style=flat-square)
![Waveshare](https://img.shields.io/badge/Waveshare%20WM8960-compatible-1f6feb?style=flat-square)
![Seeed Studio](https://img.shields.io/badge/Seeed%20Studio-compatible-1f6feb?style=flat-square)

Complete audio support for WM8960-based audio HATs (including ReSpeaker 2-Mic HAT) on the Raspberry Pi running Raspberry Pi OS.

## Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Tested Configurations](#tested-configurations)
- [Quick Install](#quick-install)
- [Quick Verification](#quick-verification)
- [Audio Server Support](#audio-server-support)
- [Echo Cancellation](#echo-cancellation)
- [Mixer Controls](#mixer-controls)
- [Testing Audio](#testing-audio)
- [Persisting Audio Settings](#persisting-audio-settings)
- [Uninstallation](#uninstallation)
- [Troubleshooting & Support](#troubleshooting--support)
- [Documentation](#documentation)
- [License](#license)
- [Contributing](#contributing)
- [Resources](#resources)
- [Credits](#credits)

## Overview

This project provides a patched DKMS kernel module, systemd service, ALSA configuration, and optional WebRTC echo cancellation for WM8960-based Raspberry Pi Audio HATs that lack an external MCLK — where the mainline Linux `snd_soc_wm8960` driver fails with "No MCLK configured". Auto-detects and configures PipeWire, PulseAudio, or ALSA-only setups at install time.

### Key Features

- **Patched DKMS kernel module** — forces PLL mode from BCLK so Pi HATs work without an external MCLK (mainline `snd_soc_wm8960` fails here)
- **Dynamic overlay loading** via systemd service with 5-retry I2C detection — no `config.txt` overlay races or boot failures
- **Boot-time DKMS auto-rebuild** — transparently handles Pi OS kernel-update edge cases
- **PipeWire, PulseAudio, and ALSA** auto-detected and configured on install
- **WebRTC AEC3 echo cancellation** (~30dB attenuation) for voice assistants
- **User utilities** — `test-audio.sh` (10-check diagnostic, or 8 with `--quick`), `wm8960-diag` (bug-report dump), `wm8960-volume` (preset manager)
- **Clean uninstall** — `# wm8960-managed` tagged config.txt lines, backup restore, idempotent re-install

## Prerequisites

- Raspberry Pi with 40-pin GPIO header
- WM8960 Audio HAT seated on GPIO pins
- Raspberry Pi OS (32-bit or 64-bit, Trixie or newer recommended)
- Internet connection and sudo access

## Tested Configurations

These combinations are verified to work on real hardware:

| Pi Model | OS | Kernel | Status |
|----------|-----|--------|--------|
| Raspberry Pi Zero 2W | Raspberry Pi OS Lite Trixie (64-bit) | 6.12.75+rpt-rpi-v8 | Primary test platform |
| Other 40-pin Pi models | Raspberry Pi OS Trixie or newer | 6.6+ | Should work (same kernel APIs) — please report results |

The driver uses DKMS with kernel compatibility wrappers for 6.13+, and the boot-time auto-rebuild handles cross-kernel scenarios automatically.

## Quick Install

```bash
# Update system and reboot first (recommended — the installer will warn if a kernel update is pending)
sudo apt update && sudo apt upgrade -y
sudo reboot

# After reboot, clone and install
sudo apt install git -y
git clone https://github.com/MJD19994/WM8960_AudioHAT_Drivers.git
cd WM8960_AudioHAT_Drivers
sudo bash install.sh
sudo reboot
```

The installer performs 13 steps and is idempotent (safe to re-run). It runs a pre-flight check that warns you if a kernel update is pending reboot, and the service will auto-rebuild the DKMS module at boot if the kernel changes later. For detailed steps, options (`--skip-pipewire`, `--yes`), and manual verification, see **[docs/INSTALLATION.md](docs/INSTALLATION.md)**.

## Quick Verification

After rebooting, run the test suite:

```bash
cd ~/WM8960_AudioHAT_Drivers
sudo bash test-audio.sh                # full 10-check test (8 automated + 2 interactive)
sudo bash test-audio.sh --quick        # 8 automated checks only (skips speaker/mic tests)
```

The 8 automated checks cover: service status, DKMS module, I2C detection, kernel modules, sound card, playback device, capture device, and ALSA configuration. The full test adds interactive speaker playback and microphone capture tests (checks 9 and 10), so you can hear the audio working end-to-end. Use `--quick` for CI or headless setups where no one can confirm interactive prompts.

For manual verification steps, see [docs/INSTALLATION.md#manual-verification](docs/INSTALLATION.md#manual-verification).

## Audio Server Support

The installer automatically detects your audio server and deploys the right config — no manual setup required.

| Audio Server | Auto-detected? | Config Installed |
|---|---|---|
| PipeWire / WirePlumber | Yes | `/etc/wireplumber/wireplumber.conf.d/40-wm8960-default.conf` |
| PulseAudio (native) | Yes | `/etc/pulse/default.pa.d/wm8960-default.pa` |
| `pipewire-pulse` | Yes (uses WirePlumber config) | WirePlumber rules handle defaults |
| ALSA-only (headless) | N/A | `asound.conf` handles routing |

For dedicated setup guides, see the **[PipeWire README](pipewire/README.md)** and **[PulseAudio README](pulseaudio/README.md)**.

## Echo Cancellation

WebRTC AEC3 echo cancellation is available for voice assistant and conferencing use cases (~30dB attenuation). Supports bare ALSA (loopback router), PipeWire, and PulseAudio.

```bash
cd tools/echo-cancel
sudo bash install.sh
```

When running, all audio must go through the loopback devices (`hw:Loopback,0,0` / `hw:Loopback,1,1`) or the `aec` virtual ALSA device. For full documentation, tuning flags, and testing instructions, see **[tools/echo-cancel/README.md](tools/echo-cancel/README.md)**.

## Mixer Controls

### Interactive (alsamixer)

For general volume and mute control, use the standard ALSA mixer:

```bash
alsamixer
```

Press **F6** to select the WM8960 sound card, then adjust:
- PCM playback volume
- Headphone / Speaker volume
- Capture volume (microphone)
- Input source selection

Press **M** to toggle mute on a selected channel. Save changes with `sudo alsactl store`.

### Volume Presets

The `wm8960-volume` utility provides tested, known-good mixer settings for common use cases — faster than adjusting individual controls in alsamixer:

```bash
sudo wm8960-volume speakers        # Moderate speaker volume, headphones muted
sudo wm8960-volume headphones      # Comfortable headphone volume, speakers muted
sudo wm8960-volume recording       # Mic capture with moderate gain, ALC off
sudo wm8960-volume voice           # Voice-assistant tuned: ALC + noise gate + HPF
sudo wm8960-volume reset           # Restore factory defaults
sudo wm8960-volume show            # Display current levels
```

Save the chosen preset across reboots with `sudo alsactl store`. For all presets, tuning flags, and a complete ALSA control reference, see [docs/CONFIGURATION.md#volume-presets](docs/CONFIGURATION.md#volume-presets) and [docs/ALSA-Mixer-Controls.md](docs/ALSA-Mixer-Controls.md).

## Testing Audio

Quick ways to verify your HAT is working end-to-end and hear real audio through it.

### Playback

```bash
# Stereo WAV test (says "front-left" / "front-right")
speaker-test -t wav -c 2

# 440 Hz sine tone for 3 seconds (useful for confirming a specific frequency plays)
speaker-test -t sine -f 440 -l 3

# Play a WAV file
aplay /usr/share/sounds/alsa/Front_Center.wav

# Play with a specific sample rate
aplay -r 48000 your-file.wav

# Play directly to the WM8960 hardware (bypasses ALSA mixing)
aplay -D plughw:wm8960soundcard,0 your-file.wav
```

### Recording

```bash
# Record 10 seconds at CD quality (44.1kHz stereo)
arecord -d 10 -f cd -t wav test.wav

# Record 16kHz mono (voice assistant format)
arecord -d 5 -r 16000 -c 1 -f S16_LE -t wav voice.wav

# Play back the recording
aplay test.wav

# Record and save with today's timestamp
arecord -d 10 -f cd -t wav "recording-$(date +%Y%m%d-%H%M%S).wav"
```

For ideas on what to do with the HAT once audio is working (Bluetooth, internet radio, TTS, voice assistants, monitoring), see [docs/CONFIGURATION.md#use-cases](docs/CONFIGURATION.md#use-cases).

For automated diagnostics and interactive speaker/mic verification, use the built-in test script:

```bash
sudo bash test-audio.sh          # full interactive test suite
sudo bash test-audio.sh --quick   # automated checks only
```

## Persisting Audio Settings

ALSA mixer settings (volume, mute state, etc.) do **not** persist across reboots by default — this is standard ALSA practice. After tuning with `alsamixer` or `wm8960-volume`, save manually:

```bash
sudo alsactl store
```

**Optional auto-save** — for consumer devices or convenience, you can enable a systemd timer that automatically saves settings every 6 hours (waits 30 minutes after boot first, so you have time to configure):

```bash
sudo systemctl enable --now wm8960-alsa-store.timer
```

Auto-save includes automatic backup rotation (keeps last 5 backups). See [docs/CONFIGURATION.md#saving-audio-settings](docs/CONFIGURATION.md#saving-audio-settings) for full details on manual vs. automatic saving and backup management.

## Uninstallation

```bash
cd ~/WM8960_AudioHAT_Drivers
sudo bash uninstall.sh
sudo reboot
```

The uninstaller removes the kernel module, device tree overlay, systemd services, ALSA configs, and `# wm8960-managed` tagged lines from `config.txt`. Packages like `dkms` and `i2c-tools` are preserved. For full details and optional manual cleanup, see [docs/INSTALLATION.md#uninstallation](docs/INSTALLATION.md#uninstallation).

## Troubleshooting & Support

**First, run diagnostics:**
```bash
sudo bash test-audio.sh --quick    # 8 automated checks (skips interactive tests)
sudo wm8960-diag                   # full system dump (paste into GitHub issues)
sudo cat /var/log/wm8960-soundcard.log
```

Common issues are documented in **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** — covers service failures, codec detection, kernel updates, audio quality problems, and more.

**Getting help:**
1. Check [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
2. Search existing [GitHub Issues](https://github.com/MJD19994/WM8960_AudioHAT_Drivers/issues)
3. Run `sudo wm8960-diag` and paste the output when [opening a new issue](https://github.com/MJD19994/WM8960_AudioHAT_Drivers/issues/new)

## Documentation

| Document | Contents |
|----------|----------|
| [docs/INSTALLATION.md](docs/INSTALLATION.md) | Detailed install, installer options, manual verification, uninstallation |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | `config.txt` reference, ALSA files, dynamic loading, advanced tuning, auto-save |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Diagnostics and fixes for common issues |
| [docs/ALSA-Mixer-Controls.md](docs/ALSA-Mixer-Controls.md) | Full WM8960 mixer control reference (Wyoming/Rhasspy tuning) |
| [docs/LICENSING.md](docs/LICENSING.md) | Per-component license breakdown |
| [pipewire/README.md](pipewire/README.md) | PipeWire setup guide |
| [pulseaudio/README.md](pulseaudio/README.md) | PulseAudio setup guide |
| [tools/echo-cancel/README.md](tools/echo-cancel/README.md) | WebRTC AEC3 echo canceller |

## License

This repository contains code under three licenses, reflecting the origin of each component. These components are distributed separately (see [docs/LICENSING.md](docs/LICENSING.md) for details). If you are redistributing combined artifacts, review license obligations for your specific distribution model.

| Component | License | Why |
|-----------|---------|-----|
| Scripts, configs, overlays, service files, docs, and all files at the repo root | **MIT** — see [LICENSE](LICENSE) | Original work, kept permissive for maximum reuse |
| [`kernel_module/`](kernel_module/) — DKMS kernel module source | **GPL-2.0-only** | Derived from the mainline Linux kernel `wm8960.c` codec driver (Copyright 2007–2011 Wolfson Microelectronics); kernel modules inherit the kernel's license |
| [`tools/echo-cancel/`](tools/echo-cancel/) — optional echo canceller | **GPLv3** — see [tools/echo-cancel/LICENSE-GPL3](tools/echo-cancel/LICENSE-GPL3) | SpeexDSP engine inherits GPLv3 from [voice-engine/ec](https://github.com/voice-engine/ec); WebRTC engine is GPLv3 by our choice for consistency. The vendored PortAudio ring buffer (`pa_ringbuffer.*`, `pa_memorybarrier.h`) retains its original BSD-style license. |

If you only use the audio driver, you're working with MIT + GPL-2.0-only (standard kernel-module licensing). If you additionally install the echo canceller, GPLv3 applies to that binary only.

For per-file details, compatibility notes, and downstream-user guidance, see [docs/LICENSING.md](docs/LICENSING.md).

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch off `main`
3. Make your changes (run `sudo bash test-audio.sh --quick` on real hardware to verify)
4. Submit a pull request

For bug reports, run `sudo wm8960-diag` and include the output in your issue.

## Resources

- [WM8960 Datasheet](https://www.cirrus.com/products/wm8960/) — Cirrus Logic (formerly Wolfson) product page
- [Raspberry Pi Documentation](https://www.raspberrypi.org/documentation/) — official Pi docs
- [ALSA Project](https://www.alsa-project.org/) — Advanced Linux Sound Architecture
- [Device Tree Overlays](https://www.raspberrypi.com/documentation/computers/configuration.html#part2) — Pi overlay documentation
- [DKMS Documentation](https://github.com/dell/dkms) — Dynamic Kernel Module Support

**Related projects:**
- [WM8960 Audio HAT for Armbian (Orange Pi Zero 2W)](https://github.com/MJD19994/WM8960_AudioHAT_Armbian_OPiZero2W) — sibling repo sharing echo-cancel source

## Credits

Developed and maintained by [MJD19994](https://github.com/MJD19994). Special thanks to:

- **Wolfson Microelectronics / Cirrus Logic** — original mainline `wm8960.c` codec driver
- **The Linux kernel community** — ALSA SoC framework and `snd-aloop` loopback module
- **[voice-engine/ec](https://github.com/voice-engine/ec)** — SpeexDSP echo cancellation reference
- **[SaneBow/alsa-aec](https://github.com/SaneBow/alsa-aec)** — ALSA AEC virtual device design
- **[PortAudio](http://www.portaudio.com)** — vendored lock-free ring buffer for the WebRTC EC
- **All contributors** who have helped improve this driver package
