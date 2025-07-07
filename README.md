# System Setup Script

A robust and secure system setup script for Debian-based Linux distributions (Ubuntu, Debian, etc.). This script automates the installation and configuration of essential system utilities, security tools, and development environments.

## Features

- 🔄 System Updates: Performs full system update and upgrade
- 📦 Package Management: Installs essential system utilities with version control
- 🔒 Security: 
  - Generates ED25519 SSH keys
  - Configures secure SSH defaults
  - Optional passwordless sudo (disabled by default)
- 🔍 Monitoring: Installs system monitoring tools (htop, atop, sysstat)
- 🌐 Networking: Sets up network utilities and SSH server
- 💾 Backup: Creates automatic backups of modified configuration files
- 📝 Logging: Comprehensive logging of all operations

## Prerequisites

- Debian-based Linux distribution (Ubuntu, Debian, etc.)
- Root access or sudo privileges
- Internet connection
- Minimum 5GB free disk space

## Installation

1. Clone or download this repository:
   ```bash
   git clone <repository-url>
   cd <repository-directory>
   ```

2. Make the script executable:
   ```bash
   chmod +x setup.sh
   ```

3. Run the script with sudo:
   ```bash
   sudo ./setup.sh
   ```

## Configuration

The script includes several configuration options at the beginning of the file:

```bash
ENABLE_PASSWORDLESS_SUDO=false  # Enable/disable passwordless sudo
INSTALL_GUI_TOOLS=false         # Install GUI-based tools
GENERATE_SSH_KEYS=true          # Generate SSH keys
MIN_SPACE_GB=5                  # Minimum required disk space in GB
```

Modify these variables according to your needs before running the script.

## Installed Packages

### System Monitoring
- htop: Interactive process viewer
- atop: Advanced system & process monitor
- sysstat: Performance monitoring tools
- smartmontools: SMART monitoring tools
- ncdu: NCurses disk usage

### Network Tools
- net-tools: Basic networking tools
- nmap: Network exploration tool
- mtr: Network diagnostic tool
- inetutils-ping: ICMP ping utilities
- rsync: Fast file transfer
- lftp: Sophisticated FTP/HTTP client
- w3m: Text-based web browser
- lynx: Text browser

### Text/Terminal Tools
- vim: Advanced text editor
- nano: Simple text editor
- tmux: Terminal multiplexer
- tree: Directory listing
- less: Text file viewer

### Disk/FS Tools
- lvm2: Logical Volume Management
- xfsprogs: XFS filesystem tools

### Security/Network
- wireguard-tools: Modern VPN tools
- openssh-server: SSH server

### Misc Utilities
- unzip: Archive extraction
- jq: JSON processor
- plocate: File search
- neofetch: System information
- mc: Midnight Commander file manager

## Security Features

### SSH Configuration
- Uses ED25519 keys with increased security parameters
- Configures secure SSH client defaults
- Implements connection multiplexing
- Disables potentially unsafe features by default

### System Security
- Creates backups of modified configuration files
- Logs all operations for audit purposes
- Optional passwordless sudo (disabled by default)
- Secure file permissions for SSH keys and config

## Logging and Backup

- Logs are stored at: `/var/log/system_setup.log`
- Backups are created at: `/root/system_setup_backup_<timestamp>/`
- All modified configuration files are automatically backed up

## Troubleshooting

1. Check the log file at `/var/log/system_setup.log` for detailed information
2. Verify backup files in the backup directory
3. Ensure you have sufficient disk space (minimum 5GB)
4. Check internet connectivity before running the script

## Contributing

Feel free to submit issues, fork the repository, and create pull requests for any improvements.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Disclaimer

This script makes significant changes to your system configuration. While it includes safety checks and backups, it's recommended to:
1. Review the script before running
2. Test in a non-production environment first
3. Ensure you have backups of important data
4. Understand the implications of the changes being made

## Support

For issues, questions, or contributions, please open an issue in the repository. 