## Installation Guide for WM8960 AudioHAT Drivers

### Overview
This guide provides comprehensive instructions on how to install the WM8960 AudioHAT Drivers using the `install.sh` script included in this repository.

### Prerequisites
- A Raspberry Pi or compatible device
- Raspbian OS installed
- Basic knowledge of using the terminal

### Installation Steps
1. Clone the repository:
   ```bash
   git clone https://github.com/MJD19994/WM8960_AudioHAT_Drivers.git
   cd WM8960_AudioHAT_Drivers
   ```
   
2. Run the installation script:
   ```bash
   sudo bash install.sh
   ```

### Verification Procedures
After installation, verify that the drivers are loaded:
```bash
lsmod | grep wm8960
```

### Configuration
To configure the driver settings, modify the `config.txt` file located in `/boot/` and add:
```
dtoverlay=wm8960
```

### Dynamic Loading Explanation
This section explains how the drivers can be dynamically loaded or unloaded using modprobe commands.

### Advanced Configuration
Instructions on advanced settings and potential configuration options for more experienced users.

### Troubleshooting
Common issues encountered during installation and usage, along with solutions.

### Uninstallation
To uninstall the driver, run:
```bash
sudo apt-get remove wm8960-drivers
```

### License
This project is licensed under the MIT License.

### Support
For any questions or issues, please open an issue on the GitHub repository or join our community forum.
