#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# WM8960 Echo Canceller — Install Script (Raspberry Pi)
#
# Two echo cancellation engines available:
#   webrtc (default) — WebRTC AEC3, ~30dB+ attenuation, requires snd-aloop
#   speex            — SpeexDSP, ~15dB attenuation, FIFO-based, no snd-aloop needed
#
# Usage: sudo bash install.sh [webrtc|speex] [--uninstall]

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_NAME="wm8960-echo-cancel"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
ALOOP_DKMS_SRC="${SCRIPT_DIR}/../../dkms/snd-aloop"

log() { echo "[EC] $1"; }
log_error() { echo "[EC] ERROR: $1" >&2; }

if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root (sudo)"
    exit 1
fi

# Parse arguments
UNINSTALL=0
ENGINE="webrtc"
for arg in "$@"; do
    case "$arg" in
        --uninstall) UNINSTALL=1 ;;
        webrtc|speex) ENGINE="$arg" ;;
        *) log_error "Unknown argument: $arg"; echo "Usage: sudo bash install.sh [webrtc|speex] [--uninstall]"; exit 1 ;;
    esac
done

# --- Uninstall ---
if [ "$UNINSTALL" -eq 1 ]; then
    log "Uninstalling echo canceller..."
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
    rm -f "${SERVICE_FILE}"
    rm -f /usr/local/bin/wm8960-ec
    rm -f /usr/local/bin/wm8960-ec-webrtc
    rm -f /tmp/ec.input /tmp/ec.output
    if grep -q "wm8960-managed" /etc/alsa/conf.d/50-aec.conf 2>/dev/null; then
        rm -f /etc/alsa/conf.d/50-aec.conf
    fi
    if grep -q "wm8960-managed" /etc/alsa/conf.d/50-wm8960-aec.conf 2>/dev/null; then
        rm -f /etc/alsa/conf.d/50-wm8960-aec.conf  # clean up legacy name (only if we own it)
    fi
    if grep -q "wm8960-managed" /etc/modules-load.d/wm8960-snd-aloop.conf 2>/dev/null; then
        rm -f /etc/modules-load.d/wm8960-snd-aloop.conf
    fi
    if grep -q "wm8960-managed" /etc/modules-load.d/snd-aloop.conf 2>/dev/null; then
        rm -f /etc/modules-load.d/snd-aloop.conf  # clean up legacy name (only if we own it)
    fi
    # Unregister snd-aloop DKMS if we registered it (built-in kernel module is unaffected).
    # Separate the dkms exit code from the grep parsing so a broken DKMS state
    # doesn't masquerade as "not registered" and then have us delete the source
    # tree out from under a still-registered package.
    aloop_still_registered=0
    if command -v dkms >/dev/null 2>&1; then
        aloop_status_rc=0
        aloop_status_out="$(dkms status snd-aloop/1.0 2>&1)" || aloop_status_rc=$?
        if [ "$aloop_status_rc" -ne 0 ]; then
            aloop_still_registered=1
            log "Warning: could not query DKMS for snd-aloop (exit $aloop_status_rc); keeping source tree"
        elif printf '%s\n' "$aloop_status_out" | grep -q .; then
            # Surface the dkms remove output so the user can see *why* it
            # failed (broken kernel build env, locked module, etc.) instead
            # of getting a generic "Echo canceller uninstalled" success line.
            if ! dkms remove snd-aloop/1.0 --all; then
                aloop_still_registered=1
                log "Warning: 'dkms remove snd-aloop/1.0 --all' failed; the snd-aloop DKMS module will persist across kernel upgrades"
            fi
        fi
    fi
    if [ "$aloop_still_registered" -eq 0 ]; then
        rm -rf /usr/src/snd-aloop-1.0
    else
        log "Skipping /usr/src/snd-aloop-1.0 removal because DKMS may still reference it"
    fi
    systemctl daemon-reload
    if [ "$aloop_still_registered" -ne 0 ]; then
        log "Echo canceller partially uninstalled (snd-aloop DKMS module not removed; see warning above)"
    else
        log "Echo canceller uninstalled"
    fi
    exit 0
fi

log "Installing $ENGINE echo canceller..."

# --- Install dependencies ---
log "Installing dependencies..."
apt-get update -qq
if [ "$ENGINE" = "webrtc" ]; then
    apt-get install -y -qq libasound2-dev libspeexdsp-dev libwebrtc-audio-processing-dev build-essential pkg-config sox dkms >/dev/null
else
    apt-get install -y -qq libasound2-dev libspeexdsp-dev build-essential pkg-config sox >/dev/null
fi

# --- Load snd-aloop for WebRTC ---
if [ "$ENGINE" = "webrtc" ]; then
    if ! lsmod | grep -q snd_aloop; then
        # Try loading the built-in module first (RPi OS often has CONFIG_SND_ALOOP=m)
        if modprobe snd-aloop 2>/dev/null; then
            log "snd-aloop loaded from kernel (built-in module)"
        elif [ -d "$ALOOP_DKMS_SRC" ]; then
            log "Built-in snd-aloop not available, building via DKMS..."
            rm -rf /usr/src/snd-aloop-1.0
            cp -r "$ALOOP_DKMS_SRC" /usr/src/snd-aloop-1.0
            dkms remove snd-aloop/1.0 --all 2>/dev/null || true
            dkms add snd-aloop/1.0
            dkms install snd-aloop/1.0
            modprobe snd-aloop || {
                log_error "Failed to load snd-aloop module"
                exit 1
            }
            log "snd-aloop built and loaded via DKMS"
        else
            log_error "snd-aloop not available and DKMS source not found at $ALOOP_DKMS_SRC"
            exit 1
        fi
    else
        log "snd-aloop already loaded"
    fi
    # Persist module across reboots
    if ! grep -qE "^snd[-_]aloop" /etc/modules-load.d/*.conf 2>/dev/null && ! grep -qE "^snd[-_]aloop" /etc/modules 2>/dev/null; then
        cat > /etc/modules-load.d/wm8960-snd-aloop.conf <<'MODEOF'
# wm8960-managed
snd-aloop
MODEOF
    fi

    # Install ALSA AEC config
    if [ -f "${SCRIPT_DIR}/configs/alsa-aec.conf" ]; then
        mkdir -p /etc/alsa/conf.d
        {
            echo "# wm8960-managed"
            cat "${SCRIPT_DIR}/configs/alsa-aec.conf"
        } > /etc/alsa/conf.d/50-aec.conf
        # Drop a previous prefixed-name install if still present so we
        # don't end up with two competing AEC drop-ins active at once.
        if [ -f /etc/alsa/conf.d/50-wm8960-aec.conf ] && \
           grep -q "wm8960-managed" /etc/alsa/conf.d/50-wm8960-aec.conf 2>/dev/null; then
            rm -f /etc/alsa/conf.d/50-wm8960-aec.conf
        fi
        log "ALSA AEC config installed"
    fi
fi

# --- speex install: clean up stale WebRTC drop-ins from a prior run ---
# Re-running install.sh as `speex` after a previous webrtc install must not
# leave the AEC ALSA drop-in or snd-aloop persistence behind, otherwise
# applications keep being routed through stale loopback plumbing while the
# active service is now FIFO-based.
if [ "$ENGINE" = "speex" ]; then
    for f in /etc/alsa/conf.d/50-aec.conf \
             /etc/alsa/conf.d/50-wm8960-aec.conf \
             /etc/modules-load.d/wm8960-snd-aloop.conf \
             /etc/modules-load.d/snd-aloop.conf; do
        if [ -f "$f" ] && grep -q "wm8960-managed" "$f" 2>/dev/null; then
            rm -f "$f"
            log "Removed stale WebRTC drop-in: $f"
        fi
    done
fi

# --- Build ---
log "Building..."
cd "${SCRIPT_DIR}"
make clean >/dev/null 2>&1 || true
if [ "$ENGINE" = "webrtc" ]; then
    make webrtc
else
    make speex
fi

# --- Install binary ---
log "Installing binary..."
if [ "$ENGINE" = "webrtc" ]; then
    install -D -m 755 wm8960-ec-webrtc /usr/local/bin/wm8960-ec-webrtc
else
    install -D -m 755 wm8960-ec /usr/local/bin/wm8960-ec
fi

# --- Create systemd service ---
log "Creating systemd service..."
if [ "$ENGINE" = "webrtc" ]; then
    cat > "${SERVICE_FILE}" << 'SVCEOF'
[Unit]
Description=WM8960 Echo Cancellation (WebRTC AEC3)
After=sound.target wm8960-soundcard.service
Requires=wm8960-soundcard.service

[Service]
Type=simple
ExecStart=/usr/local/bin/wm8960-ec-webrtc -p plughw:wm8960soundcard,0 -r 48000 -n 1
Restart=always
RestartSec=3
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
SVCEOF
else
    cat > "${SERVICE_FILE}" << 'SVCEOF'
[Unit]
Description=WM8960 Echo Cancellation (SpeexDSP)
After=sound.target wm8960-soundcard.service
Requires=wm8960-soundcard.service

[Service]
Type=simple
ExecStartPre=/bin/rm -f /tmp/ec.input /tmp/ec.output
ExecStart=/usr/local/bin/wm8960-ec -i plughw:wm8960soundcard,0 -o plughw:wm8960soundcard,0 -r 48000 -c 1 -d 0 -f 4096
Restart=always
RestartSec=3
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
SVCEOF
fi

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
# `set -e` would otherwise abort the install before the post-install
# usage block prints. The unit declares Requires=wm8960-soundcard.service,
# so a fresh image where wm8960-soundcard hasn't activated yet (e.g.
# install run before the first reboot after the main installer) makes
# this start fail legitimately. Treat it as a warning and continue so
# the user still sees the usage and uninstall guidance below.
start_status=0
if ! systemctl start "${SERVICE_NAME}"; then
    start_status=1
    log "Warning: '${SERVICE_NAME}' did not start immediately. This is usually a missing dependency on a freshly imaged Pi — reboot or run 'systemctl status ${SERVICE_NAME}' to investigate."
fi

log ""
if [ "$start_status" -eq 0 ]; then
    log "Echo canceller ($ENGINE) installed and running!"
else
    log "Echo canceller ($ENGINE) installed (start pending — see warning above)."
fi
log ""
if [ "$ENGINE" = "webrtc" ]; then
    log "Usage:"
    log "  Play audio:   aplay -D hw:Loopback,0,0 audio.wav"
    log "  Record clean: arecord -D hw:Loopback,1,1 -r 48000 -c 1 -f S16_LE recording.wav"
else
    log "Usage:"
    log "  Record echo-cancelled audio:"
    log "    timeout 5 dd if=/tmp/ec.output of=recording.raw bs=96000"
    log "    sox -t raw -r 48000 -c 1 -b 16 -e signed recording.raw recording.wav"
    log ""
    log "  Play audio through the echo canceller:"
    log "    cat audio.raw > /tmp/ec.input"
fi
log ""
log "  Check status:  systemctl status ${SERVICE_NAME}"
log "  Uninstall:     sudo bash install.sh --uninstall"
