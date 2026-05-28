#!/bin/bash
# SPDX-License-Identifier: MIT

set -e

# Capture script directory at the very start (before any directory changes)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Read version from VERSION file
if [ -f "$SCRIPT_DIR/VERSION" ]; then
    WM8960_VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"
fi
if [ -z "${WM8960_VERSION:-}" ]; then
    WM8960_VERSION="unknown"
fi

# --- Argument parsing ---
SKIP_PIPEWIRE=0
SKIP_PULSEAUDIO=0
AUTO_YES=0

for arg in "$@"; do
    case "$arg" in
        --skip-pipewire)
            SKIP_PIPEWIRE=1
            ;;
        --skip-pulseaudio)
            SKIP_PULSEAUDIO=1
            ;;
        --yes|-y)
            AUTO_YES=1
            ;;
        --help|-h)
            echo "WM8960 Audio HAT Drivers v${WM8960_VERSION}"
            echo ""
            echo "Usage: sudo bash install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-pipewire     Skip PipeWire/WirePlumber configuration"
            echo "  --skip-pulseaudio   Skip PulseAudio configuration"
            echo "  --yes, -y           Auto-confirm prompts (kernel warning) and skip reboot"
            echo "  --help, -h          Show this help message"
            echo ""
            echo "By default, the installer detects PipeWire and PulseAudio automatically"
            echo "and installs configuration files for whichever is present."
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Run 'sudo bash install.sh --help' for usage information"
            exit 1
            ;;
    esac
done

echo "==============================================="
echo "WM8960 Audio HAT Installation Script v${WM8960_VERSION}"
echo "==============================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Check for pending kernel update (running kernel vs installed kernel mismatch)
# If a kernel update was installed via apt but the system hasn't rebooted,
# DKMS would build for the old kernel, wasting time. The boot-time rebuild
# in wm8960-soundcard.sh would catch it, but better to warn the user early.
running_ver="$(uname -r)"
installed_ver="$(dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii.*linux-image-[0-9]/{print $2}' | sed 's/linux-image-//' | sort -V | tail -1)"
if [ -n "$installed_ver" ] && [ "$installed_ver" != "$running_ver" ]; then
    echo "=============================================="
    echo "WARNING: Kernel update pending reboot"
    echo "=============================================="
    echo ""
    echo "  Running kernel:   $running_ver"
    echo "  Installed kernel: $installed_ver"
    echo ""
    echo "A kernel update has been installed but not yet loaded."
    echo "If you continue, DKMS will build for the OLD kernel and"
    echo "will need to rebuild after reboot (adds ~30s to boot)."
    echo ""
    echo "Recommended: reboot first, then re-run this script."
    echo ""
    if [ "$AUTO_YES" -eq 1 ]; then
        echo "Auto-confirmed (--yes): continuing with running kernel $running_ver"
        echo "(Boot-time DKMS rebuild will handle the new kernel automatically)"
    elif [ -t 0 ]; then
        read -rp "Continue anyway? (y/n): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Exiting. Please reboot and re-run: sudo bash install.sh"
            exit 1
        fi
        echo "Continuing with running kernel $running_ver..."
    else
        echo "Non-interactive mode: continuing with running kernel $running_ver"
        echo "(Boot-time DKMS rebuild will handle the new kernel automatically)"
    fi
    echo ""
fi

echo "Step 1/14: Updating package lists..."
timeout 120 apt-get update || echo "Warning: apt-get update timed out or failed. Package installations may fail if repositories are not accessible."

echo ""
echo "Step 2/14: Installing kernel headers..."
apt-get install -y "linux-headers-$(uname -r)"

echo ""
echo "Step 3/14: Installing required packages..."
apt-get install -y dkms i2c-tools alsa-utils libasound2-plugins

echo ""
echo "Step 4/14: Configuring I2C interface in config.txt..."
# Detect boot partition location
if [ -f "/boot/firmware/config.txt" ]; then
    CONFIG_FILE="/boot/firmware/config.txt"
elif [ -f "/boot/config.txt" ]; then
    CONFIG_FILE="/boot/config.txt"
else
    echo "Error: config.txt not found in /boot/firmware or /boot"
    exit 1
fi

echo "Using config file: $CONFIG_FILE"

# Backup config.txt before making any changes
BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"
echo "Backed up config.txt to $BACKUP_FILE"
echo "Note: Backup files accumulate with each run. Old backups can be safely removed to save space."

# Helper: check if a setting exists under [all] section specifically
# (not under [pi4], [cm4], etc. which would only apply to specific models)
in_all_section() {
    local pattern="$1"
    if ! grep -qE "^[[:space:]]*\[all\]" "$CONFIG_FILE"; then
        return 1
    fi
    local all_line
    all_line=$(grep -nE "^[[:space:]]*\[all\]" "$CONFIG_FILE" | head -1 | cut -d: -f1)
    # Find next section header after [all], or use end of file
    local next_section_line
    # Match the next section header, allowing leading whitespace for consistency
    # with the [all] match above (otherwise an indented later section header
    # would be missed and we'd treat its contents as part of [all]).
    next_section_line=$(tail -n +"$((all_line + 1))" "$CONFIG_FILE" | grep -nE "^[[:space:]]*\[" | head -1 | cut -d: -f1)
    if [ -n "$next_section_line" ]; then
        next_section_line=$((all_line + next_section_line))
        sed -n "$((all_line + 1)),$((next_section_line - 1))p" "$CONFIG_FILE" | grep -qE "$pattern"
    else
        tail -n +"$((all_line + 1))" "$CONFIG_FILE" | grep -qE "$pattern"
    fi
}

# Helper: get the actual line number of a pattern within [all] section only
line_in_all_section() {
    local pattern="$1"
    local all_line
    all_line=$(grep -nE "^[[:space:]]*\[all\]" "$CONFIG_FILE" | head -1 | cut -d: -f1)
    # Defensive guard: if no [all] section exists, return empty rather than
    # falling through to tail -n +1 which would scan the entire file.
    # Current callers gate this with in_all_section() first, so this is
    # insurance against a future caller that forgets.
    if [ -z "$all_line" ]; then
        return
    fi
    local next_section_line
    # Match the next section header, allowing leading whitespace for consistency
    # with the [all] match above (otherwise an indented later section header
    # would be missed and we'd treat its contents as part of [all]).
    next_section_line=$(tail -n +"$((all_line + 1))" "$CONFIG_FILE" | grep -nE "^[[:space:]]*\[" | head -1 | cut -d: -f1)
    local section_content rel_line
    if [ -n "$next_section_line" ]; then
        next_section_line=$((all_line + next_section_line))
        section_content=$(sed -n "$((all_line + 1)),$((next_section_line - 1))p" "$CONFIG_FILE")
    else
        section_content=$(tail -n +"$((all_line + 1))" "$CONFIG_FILE")
    fi
    rel_line=$(echo "$section_content" | grep -nE "$pattern" | head -1 | cut -d: -f1)
    if [ -n "$rel_line" ]; then
        echo "$((all_line + rel_line))"
    fi
}

# Check if dtparam=i2c_arm=on is already present in [all] section
if ! in_all_section "^[^#]*dtparam=i2c_arm=on"; then
    echo "Adding dtparam=i2c_arm=on to config.txt [all] section..."

    # Try to add it to [all] section if it exists
    if grep -qE "^[[:space:]]*\[all\]" "$CONFIG_FILE"; then
        # Find the line number of [all] and insert after it
        all_line=$(grep -nE "^[[:space:]]*\[all\]" "$CONFIG_FILE" | head -1 | cut -d: -f1)
        if ! sed -i "${all_line}a dtparam=i2c_arm=on # wm8960-managed" "$CONFIG_FILE"; then
            echo "ERROR: Failed to add dtparam=i2c_arm=on to config.txt"
            exit 1
        fi
        echo "Added dtparam=i2c_arm=on to [all] section"
    else
        # No [all] section, append to end of file
        {
            echo ""
            echo "[all]"
            echo "dtparam=i2c_arm=on # wm8960-managed"
        } >> "$CONFIG_FILE"
        echo "Added [all] section with dtparam=i2c_arm=on"
    fi

    # Verify dtparam was actually added to config.txt
    if ! in_all_section "^[^#]*dtparam=i2c_arm=on"; then
        echo "ERROR: Failed to verify dtparam=i2c_arm=on in config.txt"
        exit 1
    fi
else
    echo "dtparam=i2c_arm=on already present in config.txt [all] section"
fi

# Check for dtoverlay=i2s-mmap conflict and warn user
# This warns if user already has i2s-mmap from a previous install or custom setup
# The script will add i2s-mmap later if not present, but warns if it already exists
# in case the user is experiencing conflicts and needs to know about it
if grep -E "^[^#]*dtoverlay=i2s-mmap" "$CONFIG_FILE" | grep -qv "wm8960-managed"; then
    echo ""
    echo "=========================================="
    echo "WARNING: I2S-MMAP Overlay Already Present"
    echo "=========================================="
    echo "Your config.txt already contains 'dtoverlay=i2s-mmap'."
    echo ""
    echo "This is usually correct, but if you experience audio issues after"
    echo "installation (silent failures, unexpected behavior), this overlay"
    echo "may conflict with WM8960. You can comment it out:"
    echo "  # dtoverlay=i2s-mmap  # Commented out due to WM8960 conflict"
    echo ""
    echo "See README.md 'Required config.txt Settings' section for more details."
    echo "=========================================="
    echo ""
    if [ "$AUTO_YES" -eq 1 ]; then
        echo "Auto-confirmed (--yes): continuing past I2S-MMAP warning"
    elif [ -t 0 ]; then
        read -rp "Press Enter to continue with installation..."
    else
        echo "Non-interactive mode, continuing..."
    fi
fi

echo ""
echo "Step 5/14: Compiling and installing wm8960-soundcard kernel module via DKMS..."
# Check if DKMS module is already installed. Separate the dkms exit code
# from the grep parsing so a broken DKMS state doesn't look like "not
# installed" and then collide with the fresh add/build below.
dkms_pre_rc=0
dkms_pre_out="$(dkms status 2>&1)" || dkms_pre_rc=$?
if [ "$dkms_pre_rc" -ne 0 ]; then
    echo "ERROR: dkms status failed (exit $dkms_pre_rc): $dkms_pre_out"
    echo "Resolve the DKMS issue (often: sudo apt-get install --reinstall dkms) and re-run."
    exit 1
fi
if printf '%s\n' "$dkms_pre_out" | grep -q "wm8960-soundcard"; then
    echo "DKMS module already installed, removing old version..."
    if ! dkms remove wm8960-soundcard/1.0 --all; then
        echo "Warning: DKMS remove failed (continuing with fresh install)"
    fi
fi

# Always sync kernel module source to DKMS directory (ensures updates are picked up on re-install)
DKMS_SRC_DIR="/usr/src/wm8960-soundcard-1.0"
echo "Syncing WM8960 kernel module source to $DKMS_SRC_DIR..."

if [ ! -d "$SCRIPT_DIR/kernel_module" ]; then
    echo "Error: kernel_module directory not found in $SCRIPT_DIR"
    exit 1
fi

echo "Verifying source files..."
required_files=("wm8960.c" "wm8960.h" "wm8960-soundcard.c" "Makefile" "dkms.conf")
for file in "${required_files[@]}"; do
    if [ ! -f "$SCRIPT_DIR/kernel_module/$file" ]; then
        echo "Error: Required file $file not found in $SCRIPT_DIR/kernel_module/"
        exit 1
    fi
done
echo "All required source files present"

mkdir -p "$DKMS_SRC_DIR"
for file in "${required_files[@]}"; do
    install -m 0644 "$SCRIPT_DIR/kernel_module/$file" "$DKMS_SRC_DIR/$file"
done

echo "Kernel module source files synced successfully"

# Add and build DKMS module
echo "Adding module to DKMS..."
# DKMS does not guarantee exit codes for the module-scoped form
# `dkms status MODULE/VERSION` — on a fresh system where the module isn't
# yet registered the scoped form can exit non-zero, which would falsely
# abort the installer right before `dkms add` was about to run. Use the
# global form (exit code is well-defined: 0 if dkms itself works) and
# parse the output for our module instead.
dkms_reg_rc=0
dkms_reg_out="$(dkms status 2>&1)" || dkms_reg_rc=$?
if [ "$dkms_reg_rc" -ne 0 ]; then
    echo "ERROR: dkms status failed (exit $dkms_reg_rc): $dkms_reg_out"
    exit 1
fi
if printf '%s\n' "$dkms_reg_out" | grep -q "^wm8960-soundcard/1\.0,"; then
    echo "Module already registered in DKMS"
else
    dkms add -m wm8960-soundcard -v 1.0
fi

echo "Building module with DKMS..."
if ! dkms build -m wm8960-soundcard -v 1.0; then
    echo "ERROR: DKMS build failed. Check that kernel headers are installed:"
    echo "  apt-get install linux-headers-$(uname -r)"
    exit 1
fi

echo "Installing module with DKMS..."
if ! dkms install -m wm8960-soundcard -v 1.0; then
    echo "ERROR: DKMS install failed."
    exit 1
fi

echo ""
echo "Step 6/14: Copying device tree overlay..."
# Verify the dtbo file exists in the repository
if [ ! -f "$SCRIPT_DIR/kernel_module/wm8960-soundcard.dtbo" ]; then
    echo "Error: wm8960-soundcard.dtbo not found in $SCRIPT_DIR/kernel_module/"
    exit 1
fi

# Detect boot partition location
if [ -d "/boot/firmware/overlays" ]; then
    BOOT_OVERLAYS="/boot/firmware/overlays"
elif [ -d "/boot/overlays" ]; then
    BOOT_OVERLAYS="/boot/overlays"
else
    # If neither exists, check which boot firmware location is in use
    if [ -d "/boot/firmware" ]; then
        BOOT_OVERLAYS="/boot/firmware/overlays"
        echo "Note: Boot firmware overlays directory not found, will create $BOOT_OVERLAYS"
    else
        BOOT_OVERLAYS="/boot/overlays"
        echo "Note: Boot overlays directory not found, will create $BOOT_OVERLAYS"
    fi
fi

# Create overlays directory if it doesn't exist
mkdir -p "$BOOT_OVERLAYS"

# Copy the device tree overlay
echo "Copying wm8960-soundcard.dtbo to $BOOT_OVERLAYS/..."
cp "$SCRIPT_DIR/kernel_module/wm8960-soundcard.dtbo" "$BOOT_OVERLAYS/"

# Verify the copy was successful
if [ -f "$BOOT_OVERLAYS/wm8960-soundcard.dtbo" ]; then
    echo "Device tree overlay copied successfully"
else
    echo "Error: Failed to copy device tree overlay"
    exit 1
fi

echo ""
echo "Step 7/14: Configuring kernel modules in /etc/modules..."
# Add i2c-dev to /etc/modules if not present
if ! grep -q "^i2c-dev" /etc/modules; then
    echo "i2c-dev" >> /etc/modules
    echo "Added i2c-dev to /etc/modules"
fi

echo ""
echo "Step 8/14: Configuring I2S interface in $CONFIG_FILE..."
# CONFIG_FILE already set in Step 3a

# Enable I2S-MMAP (required for proper I2S memory-mapped interface)
# Note: In rare cases, this may conflict with custom audio setups
# If you experience audio issues after installation, try commenting out dtoverlay=i2s-mmap in config.txt

# Comment out every active dtparam=i2s=on in [all]. We preserve each user
# value in commented form WITHOUT a wm8960-managed tag, so the uninstall's
# wm8960-managed removal sweep leaves the commented lines behind and the
# user can restore them by removing the leading '# '. The loop catches
# partially-edited configs with multiple active i2s=on entries, which would
# otherwise leave later occurrences active and reintroduce the conflict.
i2s_safety_count=0
while in_all_section "^[[:space:]]*dtparam=i2s=on"; do
    i2s_line=$(line_in_all_section "^[[:space:]]*dtparam=i2s=on")
    if [ -z "$i2s_line" ]; then
        break
    fi
    i2s_text=$(sed -n "${i2s_line}p" "$CONFIG_FILE")
    # Escape sed-special characters (& and \) in the captured line before
    # reinjecting it as the c\ replacement text, so a line containing them
    # can't corrupt the rewrite. Realistically a dtparam line never holds
    # these, but the line text is user-editable so we treat it as untrusted.
    i2s_text_escaped=$(printf '%s\n' "$i2s_text" | sed 's/[&\]/\\&/g')
    replacement="# ${i2s_text_escaped}  # Disabled by WM8960 installer; remove leading '# ' to restore"
    if ! sed -i "${i2s_line}c\\${replacement}" "$CONFIG_FILE"; then
        echo "ERROR: Failed to comment out dtparam=i2s=on in config.txt"
        exit 1
    fi
    echo "Commented out dtparam=i2s=on (replaced by dtoverlay=i2s-mmap)"
    # Belt-and-braces guard against an unexpected non-progressing loop.
    i2s_safety_count=$((i2s_safety_count + 1))
    if [ "$i2s_safety_count" -gt 20 ]; then
        echo "ERROR: dtparam=i2s=on cleanup did not converge after 20 iterations"
        exit 1
    fi
done

# Add dtoverlay=i2s-mmap if not present in [all] section
if ! in_all_section "^[^#]*dtoverlay=i2s-mmap"; then
    # Try to add it to [all] section if it exists
    if grep -qE "^[[:space:]]*\[all\]" "$CONFIG_FILE"; then
        # Insert after dtparam=i2c_arm=on in [all] if it exists, otherwise after [all] header
        if in_all_section "^[^#]*dtparam=i2c_arm=on"; then
            target_line=$(line_in_all_section "^[^#]*dtparam=i2c_arm=on")
        else
            target_line=$(grep -nE "^[[:space:]]*\[all\]" "$CONFIG_FILE" | head -1 | cut -d: -f1)
        fi
        if ! sed -i "${target_line}a dtoverlay=i2s-mmap # wm8960-managed" "$CONFIG_FILE"; then
            echo "ERROR: Failed to add dtoverlay=i2s-mmap to config.txt"
            exit 1
        fi
        echo "Added dtoverlay=i2s-mmap to [all] section"
    else
        # No [all] section exists, should have been created earlier when adding dtparam=i2c_arm=on
        echo "dtoverlay=i2s-mmap # wm8960-managed" >> "$CONFIG_FILE"
        echo "Added dtoverlay=i2s-mmap to end of config.txt"
    fi
    echo "Enabled I2S-MMAP overlay in config.txt"
    echo ""
    echo "NOTE: If you experience audio issues (silent failures, unexpected behavior),"
    echo "      you may need to comment out dtoverlay=i2s-mmap in config.txt."
    echo "      See README.md 'Required config.txt Settings' section for details."
    echo ""
fi

# Add informational comment about dynamic loading benefits.
# Tagged with # wm8960-managed so uninstall removes it cleanly via the
# tag-based sweep (no broad regex that could clobber user comments).
#
# Upgrade path: if any matching line is missing the wm8960-managed tag
# (legacy pre-1.3.0 install, manual edit, or a partial state with both
# tagged + untagged lines), tag every untagged occurrence so the
# tag-based uninstall catches them all. The sed range {/wm8960-managed/!}
# skips already-tagged lines so we don't append the tag twice.
if grep "wm8960-soundcard overlay loaded dynamically" "$CONFIG_FILE" \
        | grep -qv "wm8960-managed"; then
    sed -i '/wm8960-soundcard overlay loaded dynamically/{/wm8960-managed/!s/$/ # wm8960-managed/}' "$CONFIG_FILE"
    echo "Upgraded legacy untagged overlay note(s) to # wm8960-managed"
elif ! grep -qF "wm8960-soundcard overlay loaded dynamically" "$CONFIG_FILE"; then
    echo "" >> "$CONFIG_FILE"
    echo "# Note: wm8960-soundcard overlay loaded dynamically by service for proper I2C detection # wm8960-managed" >> "$CONFIG_FILE"
fi

# Note: We do NOT add dtoverlay=wm8960-soundcard here - loaded dynamically by service
echo "Note: wm8960-soundcard overlay will be loaded dynamically by the systemd service"

echo ""
echo "Step 9/14: Installing ALSA configuration files..."
# Create directory for WM8960 configuration
mkdir -p /etc/wm8960-soundcard

# Copy ALSA configuration files
if [ -f "$SCRIPT_DIR/asound.conf" ]; then
    cp "$SCRIPT_DIR/asound.conf" /etc/wm8960-soundcard/
    echo "Installed asound.conf"
else
    echo "ERROR: asound.conf not found in script directory - audio will not work without it"
    exit 1
fi

if [ -f "$SCRIPT_DIR/wm8960_asound.state" ]; then
    cp "$SCRIPT_DIR/wm8960_asound.state" /etc/wm8960-soundcard/
    echo "Installed wm8960_asound.state"
else
    echo "ERROR: wm8960_asound.state not found in script directory - audio will not work without it"
    exit 1
fi

# Write installed version
printf '%s\n' "$WM8960_VERSION" > /etc/wm8960-soundcard/version
echo "Version ${WM8960_VERSION} installed"

# --- PipeWire / WirePlumber configuration (conditional) ---
if [ "$SKIP_PIPEWIRE" -eq 1 ]; then
    echo "PipeWire configuration skipped (--skip-pipewire)"
elif dpkg -l wireplumber 2>/dev/null | grep -q '^ii'; then
    echo "PipeWire/WirePlumber detected - installing WM8960 default device rules..."
    if [ -f "$SCRIPT_DIR/pipewire/wireplumber-wm8960.conf" ]; then
        # Refuse to overwrite an existing user-managed file at our target
        # path. The source file carries '# wm8960-managed' on line 2, so any
        # file at the deployed path lacking that marker is owned by someone
        # else (or a hand-edited user copy) and shouldn't be silently
        # replaced.
        wp_target=/etc/wireplumber/wireplumber.conf.d/40-wm8960-default.conf
        if [ -f "$wp_target" ] && ! grep -q "wm8960-managed" "$wp_target" 2>/dev/null; then
            echo "ERROR: $wp_target exists and is not wm8960-managed -- refusing to overwrite. Move or remove it, then re-run."
            exit 1
        fi
        cp "$SCRIPT_DIR/pipewire/wireplumber-wm8960.conf" /etc/wm8960-soundcard/
        mkdir -p /etc/wireplumber/wireplumber.conf.d
        cp "$SCRIPT_DIR/pipewire/wireplumber-wm8960.conf" "$wp_target"
        echo "Installed WirePlumber config: $wp_target"
    else
        echo "Warning: pipewire/wireplumber-wm8960.conf not found in script directory (PipeWire config skipped)"
    fi
else
    echo "PipeWire/WirePlumber not detected - skipping PipeWire configuration"
    echo "  (Install wireplumber package and re-run to enable PipeWire support)"
fi

# --- PulseAudio configuration (conditional) ---
# Only install for native PulseAudio, NOT for pipewire-pulse (which uses WirePlumber config above)
if [ "$SKIP_PULSEAUDIO" -eq 1 ]; then
    echo "PulseAudio configuration skipped (--skip-pulseaudio)"
elif dpkg -l pulseaudio 2>/dev/null | grep -q '^ii' && ! dpkg -l pipewire-pulse 2>/dev/null | grep -q '^ii'; then
    echo "PulseAudio detected (native) - installing WM8960 default device config..."
    if [ -f "$SCRIPT_DIR/pulseaudio/pulseaudio-wm8960.pa" ]; then
        # Refuse to overwrite an existing user-managed file at our target
        # path. Same wm8960-managed marker convention as the WirePlumber
        # block above.
        pa_target=/etc/pulse/default.pa.d/wm8960-default.pa
        if [ -f "$pa_target" ] && ! grep -q "wm8960-managed" "$pa_target" 2>/dev/null; then
            echo "ERROR: $pa_target exists and is not wm8960-managed -- refusing to overwrite. Move or remove it, then re-run."
            exit 1
        fi
        cp "$SCRIPT_DIR/pulseaudio/pulseaudio-wm8960.pa" /etc/wm8960-soundcard/
        mkdir -p /etc/pulse/default.pa.d
        cp "$SCRIPT_DIR/pulseaudio/pulseaudio-wm8960.pa" "$pa_target"
        echo "Installed PulseAudio config: $pa_target"
    else
        echo "Warning: pulseaudio/pulseaudio-wm8960.pa not found in script directory (PulseAudio config skipped)"
    fi
elif dpkg -l pipewire-pulse 2>/dev/null | grep -q '^ii'; then
    echo "pipewire-pulse detected - PulseAudio compatibility provided by PipeWire (no separate PA config needed)"
else
    echo "PulseAudio not detected - skipping PulseAudio configuration"
fi

echo ""
echo "Step 10/14: Installing systemd service script..."

# Helper: install a script to /usr/bin with CRLF stripping and executable permissions
# This prevents "exit code 203/EXEC" from systemd if files have Windows line endings
# (e.g., downloaded as zip from GitHub instead of git clone with .gitattributes)
install_script() {
    local src="$1" dest="$2"
    sed 's/\r$//' "$src" > "$dest"
    chmod +x "$dest"
}

# Copy service script to /usr/bin
if [ -f "$SCRIPT_DIR/wm8960-soundcard.sh" ]; then
    install_script "$SCRIPT_DIR/wm8960-soundcard.sh" /usr/bin/wm8960-soundcard
    echo "Installed wm8960-soundcard service script"
else
    echo "Error: wm8960-soundcard.sh not found in script directory"
    exit 1
fi

# Copy volume preset utility to /usr/bin
if [ -f "$SCRIPT_DIR/wm8960-volume" ]; then
    install_script "$SCRIPT_DIR/wm8960-volume" /usr/bin/wm8960-volume
    echo "Installed wm8960-volume preset utility"
else
    echo "Warning: wm8960-volume not found in script directory (optional)"
fi

# Copy diagnostic dump script to /usr/bin
if [ -f "$SCRIPT_DIR/wm8960-diag" ]; then
    install_script "$SCRIPT_DIR/wm8960-diag" /usr/bin/wm8960-diag
    echo "Installed wm8960-diag diagnostic utility"
else
    echo "Warning: wm8960-diag not found in script directory (optional)"
fi

echo ""
echo "Step 11/14: Installing systemd service file..."
# Copy systemd service file
if [ -f "$SCRIPT_DIR/wm8960-soundcard.service" ]; then
    cp "$SCRIPT_DIR/wm8960-soundcard.service" /etc/systemd/system/
    echo "Installed wm8960-soundcard.service"
else
    echo "Error: wm8960-soundcard.service not found in script directory"
    exit 1
fi

# Install logrotate configuration for service log
if [ -f "$SCRIPT_DIR/wm8960-soundcard.logrotate" ]; then
    cp "$SCRIPT_DIR/wm8960-soundcard.logrotate" /etc/logrotate.d/wm8960-soundcard
    echo "Installed wm8960-soundcard logrotate configuration"
fi

# Pre-create the log file at the same mode logrotate's `create` directive uses
# (0644 root:root). Without this, first boot creates it at 0600 (default umask
# for systemd-managed services), and logrotate flips perms to 0644 on first
# rotation — small inconsistency that scripts / monitoring tools can trip on.
# Preserve existing log content on re-run (don't clobber debug history).
if [ ! -e /var/log/wm8960-soundcard.log ]; then
    install -m 0644 -o root -g root /dev/null /var/log/wm8960-soundcard.log
else
    chown root:root /var/log/wm8960-soundcard.log
    chmod 0644 /var/log/wm8960-soundcard.log
fi

echo ""
echo "Step 12/14: Installing ALSA auto-save components (disabled by default)..."
# Copy auto-save script to /usr/bin
if [ -f "$SCRIPT_DIR/wm8960-alsa-store" ]; then
    install_script "$SCRIPT_DIR/wm8960-alsa-store" /usr/bin/wm8960-alsa-store
    echo "Installed wm8960-alsa-store script"
else
    echo "Warning: wm8960-alsa-store script not found in script directory"
fi

# Copy auto-save service file
if [ -f "$SCRIPT_DIR/wm8960-alsa-store.service" ]; then
    cp "$SCRIPT_DIR/wm8960-alsa-store.service" /etc/systemd/system/
    echo "Installed wm8960-alsa-store.service"
else
    echo "Warning: wm8960-alsa-store.service not found in script directory"
fi

# Copy auto-save timer file
if [ -f "$SCRIPT_DIR/wm8960-alsa-store.timer" ]; then
    cp "$SCRIPT_DIR/wm8960-alsa-store.timer" /etc/systemd/system/
    echo "Installed wm8960-alsa-store.timer"
else
    echo "Warning: wm8960-alsa-store.timer not found in script directory"
fi

echo ""
echo "Step 13/14: Enabling systemd service..."
systemctl daemon-reload
# Only enable; don't start. The service loads the DT overlay at boot once
# I2S is active. Starting it now (pre-reboot) would fail — I2C is ready but
# the I2S overlay isn't yet, and the codec overlay would try to load against
# a stale config. A reboot after install gives a clean path.
if ! systemctl enable wm8960-soundcard.service; then
    echo "ERROR: Failed to enable wm8960-soundcard.service for boot."
    echo "       Investigate with: systemctl status wm8960-soundcard.service"
    echo "       (a malformed unit file or a busy systemd state can cause this)"
    exit 1
fi
echo "Service enabled to start on boot (will run on next reboot)"

echo ""
echo "Step 14/14: Validating installation..."
# Verify critical files and configurations
validation_errors=0

# Check if DKMS module was installed (separate exit code from grep parsing)
dkms_val_rc=0
dkms_val_out="$(dkms status 2>&1)" || dkms_val_rc=$?
if [ "$dkms_val_rc" -ne 0 ]; then
    echo "[FAIL] dkms status failed (exit $dkms_val_rc): $dkms_val_out"
    validation_errors=$((validation_errors + 1))
elif printf '%s\n' "$dkms_val_out" | grep -q "wm8960-soundcard/1.0"; then
    echo "[PASS] DKMS module installed"
else
    echo "[FAIL] DKMS module not found"
    validation_errors=$((validation_errors + 1))
fi

# Check if device tree overlay was copied
if [ -f "$BOOT_OVERLAYS/wm8960-soundcard.dtbo" ]; then
    echo "[PASS] Device tree overlay installed"
else
    echo "[FAIL] Device tree overlay not found"
    validation_errors=$((validation_errors + 1))
fi

# Check if systemd service was installed
if [ -f "/etc/systemd/system/wm8960-soundcard.service" ]; then
    echo "[PASS] Systemd service installed"
else
    echo "[FAIL] Systemd service not found"
    validation_errors=$((validation_errors + 1))
fi

# Check if config files were copied
if [ -f "/etc/wm8960-soundcard/asound.conf" ] && [ -f "/etc/wm8960-soundcard/wm8960_asound.state" ]; then
    echo "[PASS] ALSA configuration files installed"
else
    echo "[FAIL] ALSA configuration files not found"
    validation_errors=$((validation_errors + 1))
fi

# Check config.txt was modified correctly. Must be block-aware — dtparam=i2c_arm=on
# under [pi4]/[cm4]/etc. doesn't satisfy our install contract (we require [all]).
if in_all_section "^[^#]*dtparam=i2c_arm=on"; then
    echo "[PASS] I2C enabled in config.txt [all] section"
else
    echo "[FAIL] I2C not enabled in config.txt [all] section"
    validation_errors=$((validation_errors + 1))
fi

# PipeWire/PulseAudio config checks (informational only, not a failure)
if [ -f "/etc/wireplumber/wireplumber.conf.d/40-wm8960-default.conf" ]; then
    echo "[PASS] WirePlumber configuration installed (WM8960 set as default device)"
fi
if [ -f "/etc/pulse/default.pa.d/wm8960-default.pa" ]; then
    echo "[PASS] PulseAudio configuration installed (WM8960 set as default device)"
fi

if [ "$validation_errors" -eq 0 ]; then
    echo ""
    echo "All validation checks passed!"
else
    echo ""
    echo "Warning: $validation_errors validation check(s) failed. Review errors above."
fi

echo ""
echo "==============================================="
echo "Installation Complete!"
echo "==============================================="
echo ""
echo "IMPORTANT: You must reboot your Raspberry Pi for changes to take effect."
echo ""
echo "==============================================="
echo "Audio Settings Management"
echo "==============================================="
echo ""
echo "By default, audio mixer settings are NOT automatically saved."
echo "After configuring your audio settings (volume, etc.), save them with:"
echo "   sudo alsactl store"
echo ""
echo "OPTIONAL: Enable automatic saving every 6 hours:"
echo "   sudo systemctl enable wm8960-alsa-store.timer"
echo "   sudo systemctl start wm8960-alsa-store.timer"
echo ""
echo "To check auto-save status:"
echo "   sudo systemctl status wm8960-alsa-store.timer"
echo ""
echo "See README.md 'Saving Audio Settings' section for more details."
echo ""
echo "==============================================="
echo "Post-Installation Verification"
echo "==============================================="
echo ""
echo "After rebooting, cd to this repo directory and run the automated test script:"
echo ""
echo "   cd $SCRIPT_DIR"
echo "   sudo bash test-audio.sh          # Full test with speaker & mic checks"
echo "   sudo bash test-audio.sh --quick   # Quick automated checks only"
echo ""
echo "Or verify manually with these commands:"
echo ""
echo "1. Check service status:"
echo "   sudo systemctl status wm8960-soundcard.service"
echo ""
echo "2. Check I2C device detection:"
echo "   sudo i2cdetect -y 1"
echo ""
echo "3. Check kernel modules:"
echo "   lsmod | grep snd_soc"
echo ""
echo "4. List sound cards:"
echo "   cat /proc/asound/cards"
echo ""
echo "5. Check DKMS status:"
echo "   sudo dkms status"
echo ""
echo "6. Test audio playback:"
echo "   aplay -l"
echo "   speaker-test -t wav -c 2"
echo ""
echo "7. Review service logs:"
echo "   sudo cat /var/log/wm8960-soundcard.log"
echo ""
echo "For detailed troubleshooting, see the README.md file."
echo ""
if [ "$AUTO_YES" -eq 1 ]; then
    echo "Auto-confirmed (--yes): please reboot manually when ready: sudo reboot"
elif [ -t 0 ]; then
    echo "Reboot now? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Rebooting..."
        reboot
    else
        echo "Please reboot manually when ready: sudo reboot"
    fi
else
    echo "Non-interactive mode detected. Please reboot manually when ready: sudo reboot"
fi
