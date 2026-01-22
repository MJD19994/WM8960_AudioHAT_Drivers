# WM8960 Audio HAT Drivers

## Overview
This repository provides drivers for the WM8960 Audio HAT, allowing users to effectively utilize audio features in their projects.

## Why This Repository
This repository addresses several issues related to audio functionality and compatibility for various platforms. Specific issues fixed include:
- Improved audio playback quality on Raspberry Pi
- Support for additional audio formats
- Enhanced stability during high-load scenarios

## Prerequisites
- Raspberry Pi (recommended models)
- Raspbian OS (latest version)
- Internet connection for software updates

## Full Installation Steps
1. Clone the repository:
   ```bash
   git clone https://github.com/MJD19994/WM8960_AudioHAT_Drivers.git
   cd WM8960_AudioHAT_Drivers
   ```
2. Install necessary dependencies:
   ```bash
   sudo apt-get install build-essential
   ```
3. Compile the drivers:
   ```bash
   make
   ```
4. Install the drivers:
   ```bash
   sudo make install
   ```
5. Reboot the system:
   ```bash
   sudo reboot
   ```

## Verification Procedures
To ensure proper installation, conduct the following checks:
1. Check if the driver is loaded:
   ```bash
   lsmod | grep wm8960
   ```
2. Play an audio file and check sound output.
3. Ensure no errors in system logs:
   ```bash
   dmesg | grep wm8960
   ```
4. Verify device recognition:
   ```bash
   aplay -l
   ```
5. Run tests for audio quality using test tones.
6. Verify configuration file exists in `/etc/modules`.
7. Check permissions for audio device access.

## Configuration Explanations
Configuration can be modified in the configuration files located in `/etc/wm8960/`. Adjust parameters such as sample rates, bit depth, and more based on your needs.

## Dynamic Loading Explanation
The driver supports dynamic loading, enabling seamless integration without requiring a full reboot of the system. This permits updates and changes while the system is running.

## Advanced Configuration
For expert users, advanced settings can be configured in `wm8960.conf`. Options include:
- Buffer sizes
- Audio channels
- Custom sampling rates

## Troubleshooting References
If you encounter issues, refer to:
- [Linux Kernel Documentation](https://www.kernel.org/doc/html/latest/)
- Community forums and support pages for Raspberry Pi.
- Specific logs generated under `/var/log/` for additional error details.

## Uninstallation
To uninstall the drivers, run:
```bash
sudo make uninstall
```

## License Information
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support
For support, please open an issue in this repository, or reach out via the contact information provided in the repository.
