Here’s the updated `README.md` file based on the improved script:

---

# macOS Apps Installation Script

This script automates the installation and upgrade of essential applications on macOS. It dynamically manages configurations, ensures dependencies, and provides robust error handling with enhanced logging and feedback mechanisms.

## Features

- **Dynamic Configuration**: Easily customize the script via `config.txt` to specify retries, delays, parallel execution limits, and applications to install.
- **Enhanced Logging**: Comprehensive JSON logs with timestamps and categorized messages (`info`, `warning`, `error`).
- **Parallel Execution**: Efficient parallel installation with job management and progress monitoring.
- **System Resource Checks**: Validates disk space, CPU usage, and memory availability before installation.
- **Rollback Mechanism**: Automatically cleans up partially installed applications if a failure occurs.
- **Retry Logic**: Intelligent retry mechanism with exponential backoff and dynamic delays.
- **Dry Run Mode**: Simulate installations to preview changes without making modifications.
- **Internet Connectivity Check**: Validates network access with a fallback URL for restricted environments.
- **Localized Feedback**: Ready for multi-language support in error and status messages.

## Prerequisites

- macOS version 13.0 or higher.
- Administrator privileges.
- Internet connection.

## Usage

1. Clone this repository:
   ```bash
   git clone https://github.com/your-repo/macos-setup-script
   cd macos-setup-script
   ```

2. Create and customize the `config.txt` file:
   ```plaintext
   # Configuration
   MAX_RETRIES=3
   RETRY_DELAY=5
   MAX_PARALLEL_JOBS=4
   DRY_RUN=false
   VERBOSE_MODE=true

   # Applications to install
   git
   python
   node
   google-chrome
   visual-studio-code
   spotify
   docker
   vlc
   iterm2
   ```

3. Make the script executable:
   ```bash
   chmod +x install_mac_apps.sh
   ```

4. Run the script:
   ```bash
   sudo ./install_mac_apps.sh
   ```

## Configuration

The `config.txt` file supports the following options:

- **MAX_RETRIES**: Maximum number of retry attempts for failed installations.
- **RETRY_DELAY**: Delay (in seconds) between retry attempts.
- **MAX_PARALLEL_JOBS**: Maximum number of parallel installation jobs.
- **DRY_RUN**: Enable (`true`) or disable (`false`) dry run mode.
- **VERBOSE_MODE**: Enable (`true`) or disable (`false`) detailed logs.
- **Applications**: List of applications to install, using Homebrew package names.

## Logs

- Installation logs are saved in `install_log.json` with detailed timestamps and categorized messages for debugging and monitoring.

## Applications Installed

The script installs applications dynamically from the `config.txt` file. Common examples include:

- Git
- Python
- Node.js
- Google Chrome
- Visual Studio Code
- Spotify
- Docker
- VLC Media Player
- iTerm2

## Error Handling and Rollback

- **Rollback**: Automatically uninstalls partially installed applications if a failure occurs.
- **Resource Validation**: Prevents installation when resources like disk space, memory, or CPU are insufficient.

## License

This project is licensed under the MIT License. See the LICENSE file for details.

---

Let me know if you want further refinements!