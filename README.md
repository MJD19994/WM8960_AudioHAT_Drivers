# WM8960 Audio HAT Drivers

## Introduction
This repository provides the drivers for the WM8960 Audio HAT, supporting audio applications on various platforms.

## System Update and Build Tools Installation
1. **Updating the System**: Before proceeding, ensure your system is up to date. Run the following commands based on your Linux distribution:
   - For Ubuntu/Debian:
     ```bash
     sudo apt update && sudo apt upgrade
     ```
   - For Fedora:
     ```bash
     sudo dnf update
     ```
2. **Install Build Tools**: Ensure you have the essential build tools installed:
   - For Ubuntu/Debian:
     ```bash
     sudo apt install build-essential git
     ```
   - For Fedora:
     ```bash
     sudo dnf groupinstall "Development Tools"
     ```
3. **Install Additional Libraries**: Depending on your project requirements, you might need additional libraries. Check the project's documentation for specific dependencies.

## Git Installation Prerequisites
1. **Check if Git is already installed**:
   ```bash
   git --version
   ```
   If Git is installed, you will see the version number.
2. **Install Git**:
   - For Ubuntu/Debian:
     ```bash
     sudo apt install git
     ```
   - For Fedora:
     ```bash
     sudo dnf install git
     ```

## Manual Download Option
If you prefer not to use Git, you can manually download the repository:
1. Go to the repository's GitHub page: [WM8960_AudioHAT_Drivers](https://github.com/MJD19994/WM8960_AudioHAT_Drivers)
2. Click on the green "Code" button and select "Download ZIP".
3. Extract the ZIP file to your desired directory.

## Verification Steps
After installation and setup, it’s crucial to verify that everything works as expected.
1. **Verify Git Installation**:
   Run the following command:
   ```bash
   git --version
   ```
   Expected output:
   ```
   git version x.y.z
   ```
   (where x.y.z is the version you installed)
2. **Verify Build Tools Installation**:
   To check if build-essential is installed, run:
   ```bash
   dpkg -l | grep build-essential
   ```
   Expected output includes build-essential package information.

## Conclusion
By following the above instructions, you should be able to set up the WM8960 Audio HAT drivers successfully. If you encounter any issues, please refer to the project's documentation or open an issue on GitHub.

