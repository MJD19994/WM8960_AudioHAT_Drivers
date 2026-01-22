# Installation Guide

## System Updates
Before starting the installation, ensure that your system is up to date. You can do this by running the following commands:
```bash
sudo apt update && sudo apt upgrade -y
```

## Git Prerequisites
Make sure you have Git installed on your system. You can install Git using the following command:
```bash
sudo apt install git
```

## DKMS Explanation
DKMS (Dynamic Kernel Module Support) allows you to automatically rebuild kernel modules when a new kernel is installed. This is crucial for maintaining functionality of the WM8960 AudioHAT after kernel updates.

### Installing DKMS
To install DKMS, run:
```bash
sudo apt install dkms
```

## Verification Steps
After installation, verify that the WM8960 module is loaded and working correctly by running:
```bash
lsmod | grep wm8960
```
If you see the module listed, it means it is loaded successfully.

## Troubleshooting References
If you encounter issues, check the following:
- Ensure the module is loaded: `lsmod | grep wm8960`
- Check `dmesg` for any error messages related to the WM8960: `dmesg | grep wm8960`
- Review the installation instructions to ensure all steps were followed correctly.