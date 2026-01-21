# Troubleshooting Guide for WM8960 AudioHAT Drivers

This document provides a comprehensive troubleshooting guide for common issues encountered with the WM8960 AudioHAT drivers.

## 1. Service Failures
**Diagnosis:** Check system logs for errors related to audio services.  
**Solution:** Restart the audio service with the following command:
```bash
sudo systemctl restart audio.service
```

## 2. Codec Detection Issues
**Diagnosis:** Verify if the codec is detected by running `aplay -l`.  
**Solution:** If not detected, check connections and re-flash the firmware if necessary.

## 3. Wrong Card Order
**Diagnosis:** Use `cat /proc/asound/cards` to check the order of sound cards.  
**Solution:** Configure `/etc/asound.conf` or `~/.asoundrc` to set the default card.

## 4. No Sound
**Diagnosis:** Ensure volume is up and not muted.  
**Solution:** Use `alsamixer` to adjust the volume levels and unmute channels.

## 5. Recording Problems
**Diagnosis:** Check the recording device settings with `arecord -l`.  
**Solution:** Ensure the correct recording source is selected in the application settings.

## 6. Overlay Errors
**Diagnosis:** Overlay errors can often be attributed to incorrect configuration.  
**Solution:** Check the overlay settings in the device tree and adjust as needed.

## 7. ALSA Warnings
**Diagnosis:** Look for warnings in the output of `dmesg` or `journalctl -xe`.  
**Solution:** Update ALSA packages or reconfigure audio settings.

## 8. Module Loading Issues
**Diagnosis:** Check if the WM8960 module is loaded with `lsmod | grep wm8960`.  
**Solution:** Load the module with:
```bash
sudo modprobe wm8960
```

## 9. Audio Quality Issues
**Diagnosis:** Identify if there are stuttering or distortion artifacts.
**Solution:** Lower the sample rate or increase buffer sizes in the audio playback settings.

## 10. General Tips
- Ensure your system is up to date with the latest kernel and libraries.  
- Refer to the official documentation for any specific driver configurations.  

For further assistance, consult the user forums or the community support channels.