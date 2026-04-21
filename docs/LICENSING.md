# Licensing Details

This document expands on the [License section in the README](../README.md#license) with the per-component details, compatibility notes, and guidance for downstream users.

## Per-component breakdown

**MIT (default for this repo).** Everything outside `kernel_module/` and `tools/echo-cancel/` is MIT-licensed. This includes all installer scripts, systemd services, ALSA/PulseAudio/PipeWire configs, device tree overlay sources, utility scripts, and documentation.

**GPL-2.0-only (`kernel_module/`).** The DKMS kernel module is a patched version of the mainline Linux `wm8960.c` codec driver plus our added PLL and kernel compatibility fixes, and a small machine driver (`wm8960-soundcard.c`). Each source file carries an `SPDX-License-Identifier: GPL-2.0-only` header and the original Wolfson Microelectronics copyright notice alongside our modifications.

**GPLv3 (`tools/echo-cancel/`).** Both echo-cancellation engines in this directory are GPLv3:
- `ec.c`, `audio.c`, `fifo.c`, `util.c` (SpeexDSP engine) — based on [voice-engine/ec](https://github.com/voice-engine/ec), which is GPLv3.
- `ec_webrtc.cpp` (WebRTC AEC3 engine) — original work, licensed GPLv3 by our choice. Note that `libwebrtc-audio-processing` itself is BSD-licensed; GPLv3 is chosen here only for consistency with the rest of the directory.
- `pa_ringbuffer.c`, `pa_ringbuffer.h`, `pa_memorybarrier.h` — vendored from [PortAudio](http://www.portaudio.com) under the PortAudio MIT-style license, kept close to upstream. Original headers preserved.

**GPL-2.0-or-later (`dkms/snd-aloop/`).** The bundled `snd-aloop` kernel module source (used as a DKMS fallback when the kernel's built-in module isn't available) is taken from the Linux kernel tree and is GPL-2.0-or-later per its original headers.

## Compatibility notes

- **GPL-2.0-only and GPLv3 cannot be combined in a single binary.** This is fine in practice because the DKMS module and the echo canceller are distributed as separate binaries with separate build systems — they never combine into a single program. Do not attempt to statically link echo-cancel code into the kernel module.
- **BSD/MIT → GPL is one-way.** The PortAudio ring buffer files are BSD-style (GPL-compatible) and can legally sit inside the GPLv3 `tools/echo-cancel/` directory.
- **Kernel module GPL requirement.** The DKMS modules use `MODULE_LICENSE("GPL")`, which is required to access `EXPORT_SYMBOL_GPL` kernel symbols used by the ASoC subsystem.

## For downstream users

- If you are only using the audio driver, you are working with MIT (repo glue) + GPL-2.0-only (kernel module). Standard kernel-module licensing applies.
- If you additionally install the echo canceller, the GPLv3 terms in [`tools/echo-cancel/LICENSE-GPL3`](../tools/echo-cancel/LICENSE-GPL3) apply to that binary and any modifications you make to files in that directory.
- The three licenses do not "infect" each other because the components are not combined into a single program.
