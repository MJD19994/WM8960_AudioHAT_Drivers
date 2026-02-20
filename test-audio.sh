#!/bin/bash
# WM8960 Audio HAT - Post-Installation Audio Test Script
# Runs automated and interactive checks to verify the audio system is working
# Usage: sudo bash test-audio.sh [--quick]

# Parse arguments
QUICK_MODE=0
for arg in "$@"; do
    case "$arg" in
        --quick|-q)
            QUICK_MODE=1
            ;;
        --help|-h)
            echo "Usage: sudo bash test-audio.sh [--quick]"
            echo ""
            echo "Options:"
            echo "  --quick, -q   Skip interactive speaker and microphone tests"
            echo "  --help, -h    Show this help message"
            echo ""
            echo "Checks 1-6 are automated (no user interaction needed)."
            echo "Checks 7-8 test actual audio playback and recording (interactive)."
            exit 0
            ;;
    esac
done

# Counters
tests_passed=0
tests_failed=0
tests_skipped=0

# Colors (only if terminal supports them)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

# Temp file for mic test, cleaned up on exit
TEMP_RECORDING="/tmp/wm8960-test-$$.wav"
trap 'rm -f "$TEMP_RECORDING"' EXIT

pass() {
    echo -e "  ${GREEN}PASS${NC}: $1"
    tests_passed=$((tests_passed + 1))
}

fail() {
    echo -e "  ${RED}FAIL${NC}: $1"
    tests_failed=$((tests_failed + 1))
}

skip() {
    echo -e "  ${YELLOW}SKIP${NC}: $1"
    tests_skipped=$((tests_skipped + 1))
}

echo "==============================================="
echo "WM8960 Audio HAT - Audio Test"
echo "==============================================="
echo ""

# ---------- Check 1: I2C Detection ----------
echo "Check 1/8: I2C codec detection..."
if ! command -v i2cdetect >/dev/null 2>&1; then
    fail "i2cdetect not found (install i2c-tools)"
elif ! i2cdetect -y 1 0x1a 0x1a 2>/dev/null | grep -qE '(1a|UU)'; then
    fail "WM8960 not detected at I2C address 0x1a (HAT connected?)"
else
    pass "WM8960 codec detected at I2C address 0x1a"
fi

# ---------- Check 2: Kernel Modules ----------
echo "Check 2/8: Kernel modules..."
codec_loaded=false
soundcard_loaded=false

if lsmod | grep -q "snd_soc_wm8960[^_]"; then
    codec_loaded=true
fi
if lsmod | grep -q "snd_soc_wm8960_soundcard"; then
    soundcard_loaded=true
fi

if $codec_loaded && $soundcard_loaded; then
    pass "Both kernel modules loaded (snd_soc_wm8960, snd_soc_wm8960_soundcard)"
elif $codec_loaded; then
    fail "Codec module loaded but soundcard module missing"
elif $soundcard_loaded; then
    fail "Soundcard module loaded but codec module missing"
else
    fail "No WM8960 kernel modules loaded (service running?)"
fi

# ---------- Check 3: Sound Card Visible ----------
echo "Check 3/8: ALSA sound card..."
if [ -f /proc/asound/cards ]; then
    if grep -qi "wm8960" /proc/asound/cards; then
        card_info=$(grep -i "wm8960" /proc/asound/cards | head -1 | sed 's/^[[:space:]]*//')
        pass "Sound card visible: $card_info"
    else
        fail "WM8960 not found in /proc/asound/cards"
    fi
else
    fail "/proc/asound/cards not found"
fi

# ---------- Check 4: Playback Device ----------
echo "Check 4/8: Playback device..."
if aplay -l 2>/dev/null | grep -qi "wm8960"; then
    pass "Playback device available"
else
    fail "No WM8960 playback device found (aplay -l)"
fi

# ---------- Check 5: Capture Device ----------
echo "Check 5/8: Capture device..."
if arecord -l 2>/dev/null | grep -qi "wm8960"; then
    pass "Capture device available"
else
    fail "No WM8960 capture device found (arecord -l)"
fi

# ---------- Check 6: ALSA Configuration ----------
echo "Check 6/8: ALSA configuration..."
if [ -L /etc/asound.conf ]; then
    target=$(readlink -f /etc/asound.conf)
    if [ "$target" = "/etc/wm8960-soundcard/asound.conf" ]; then
        pass "asound.conf symlink correct -> $target"
    else
        fail "asound.conf symlink points to $target (expected /etc/wm8960-soundcard/asound.conf)"
    fi
elif [ -f /etc/asound.conf ]; then
    fail "asound.conf exists but is not a symlink (may be from another driver)"
else
    fail "asound.conf not found"
fi

# ---------- Interactive Tests ----------
interactive=true
if [ "$QUICK_MODE" = "1" ]; then
    interactive=false
elif ! [ -t 0 ]; then
    interactive=false
fi

# ---------- Check 7: Speaker Test ----------
echo "Check 7/8: Speaker playback test..."
if ! $interactive; then
    skip "Speaker test (use interactive mode to test)"
else
    echo "  Playing test tone through speakers for 4 seconds..."
    echo "  (If you don't hear anything, check speaker connections and volume)"
    echo ""
    # Use timeout to limit speaker-test duration, suppress its verbose output
    timeout 4 speaker-test -D hw:wm8960soundcard -c 2 -t wav -l 1 >/dev/null 2>&1
    echo ""
    read -r -p "  Did you hear the test sound? (y/n): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        pass "Speaker playback confirmed by user"
    else
        fail "Speaker playback not heard (check volume: amixer -c wm8960soundcard contents)"
    fi
fi

# ---------- Check 8: Microphone Capture Test ----------
echo "Check 8/8: Microphone capture test..."
if ! $interactive; then
    skip "Microphone test (use interactive mode to test)"
else
    echo "  Recording 3 seconds from microphone..."
    echo "  Speak into the microphone now!"
    echo ""
    if arecord -D hw:wm8960soundcard -f S16_LE -r 16000 -c 2 -d 3 "$TEMP_RECORDING" 2>/dev/null; then
        # Check if recording has any audio content (file size > just WAV header)
        file_size=$(stat -c%s "$TEMP_RECORDING" 2>/dev/null || stat -f%z "$TEMP_RECORDING" 2>/dev/null || echo "0")
        if [ "$file_size" -lt 1000 ]; then
            fail "Recording file too small ($file_size bytes) - microphone may not be working"
        else
            echo "  Playing back recording..."
            aplay -D hw:wm8960soundcard "$TEMP_RECORDING" 2>/dev/null
            echo ""
            read -r -p "  Did you hear your voice played back? (y/n): " response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                pass "Microphone capture and playback confirmed by user"
            else
                fail "Microphone playback not heard (check mic input: amixer -c wm8960soundcard sget 'Capture')"
            fi
        fi
    else
        fail "arecord failed - could not record from microphone"
    fi
fi

# ---------- Summary ----------
echo ""
echo "==============================================="
echo "Test Results"
echo "==============================================="
total=$((tests_passed + tests_failed + tests_skipped))
echo -e "  ${GREEN}Passed${NC}: $tests_passed/$total"
if [ $tests_failed -gt 0 ]; then
    echo -e "  ${RED}Failed${NC}: $tests_failed/$total"
fi
if [ $tests_skipped -gt 0 ]; then
    echo -e "  ${YELLOW}Skipped${NC}: $tests_skipped/$total"
fi
echo ""

if [ $tests_failed -eq 0 ]; then
    echo "All tests passed!"
else
    echo "Some tests failed. For troubleshooting:"
    echo "  - Check service status: sudo systemctl status wm8960-soundcard.service"
    echo "  - Check service logs:   sudo cat /var/log/wm8960-soundcard.log"
    echo "  - See TROUBLESHOOTING.md for detailed guidance"
fi

exit $tests_failed
