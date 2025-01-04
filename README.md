# macOS Apps Installation Script

This script automates the installation and upgrade of essential applications on macOS. It ensures dependencies, checks system compatibility, and handles errors gracefully, providing a reliable experience.

## Features

- **Internet Connectivity Check**: Verifies internet connection using `ping`, `curl`, or `wget`.
- **macOS Updates**: Checks for macOS updates and installs them if available.
- **Dependency Validation**: Ensures necessary dependencies (e.g., Homebrew, xcode-select, curl) are installed.
- **Rollback Mechanism**: Automatically uninstalls partially installed applications in case of failure.
- **Retry Logic**: Retries failed installations up to a configurable limit with exponential backoff.
- **Performance Checks**: Validates CPU, RAM, and disk usage before proceeding.
- **Disk Space Validation**: Ensures sufficient disk space for installations.
- **Verbose and Quiet Modes**: Toggle between detailed logs or minimal output.
- **Dry Run Mode**: Simulates installation steps without making changes.

## Prerequisites

- macOS version 13.0 or higher.
- Administrator privileges.
- Internet connection.

## Usage

1. Clone this repository:
   ```bash
   git clone https://github.com/guilherme-reis/macos-setup-script
   cd macos-setup-script
   ```

2. Make the script executable:
   ```bash
   chmod +x install_mac_apps.sh
   ```

3. Run the script:
   ```bash
   sudo ./install_mac_apps.sh
   ```

4. Monitor the progress and follow any prompts.

## Configuration

Update the `config.txt` file to customize the following:

- `REQUIRED_VERSION`: Minimum macOS version required.
- `MAX_RETRIES`: Maximum retry attempts for failed installations.
- `RETRY_DELAY`: Delay (in seconds) between retry attempts.
- `DRY_RUN`: Enable (`true`) or disable (`false`) dry run mode.
- `VERBOSE_MODE`: Enable (`true`) or disable (`false`) detailed logs.

## Applications Installed

The script installs the following applications:

- CleanMyMac X
- iTerm2
- Python
- wget
- Microsoft Teams
- OneDrive
- Insomnia
- WhatsApp
- XMind
- The Unarchiver
- Spotify
- VLC
- Google Chrome
- Visual Studio Code
- Git
- GitHub Desktop
- Docker

## Logs

Installation logs are saved to `install_log.json` for debugging and record-keeping in JSON format.

## License

This project is licensed under the MIT License. See the LICENSE file for details.

---

For feedback or issues, please open a GitHub issue or contact the repository maintainer.
