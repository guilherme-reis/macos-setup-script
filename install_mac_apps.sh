#!/bin/bash

# Configuration file path
CONFIG_FILE="config.txt"

# Log file for installation process
LOG_FILE="install_log.txt"
> "$LOG_FILE"

# Constants
REQUIRED_SPACE=$((10 * 1024 * 1024))
MAX_RETRIES=${MAX_RETRIES:-3}
RETRY_DELAY=${RETRY_DELAY:-5} # seconds
REQUIRED_VERSION="13.0"
NOTIFY_SUCCESS="notify-send"
VERBOSE_MODE=${VERBOSE_MODE:-true} # true for detailed logs, false for quiet mode
DRY_RUN=${DRY_RUN:-false} # Enable dry run mode if true
COOLDOWN_PERIOD=${COOLDOWN_PERIOD:-30} # Cooldown period in seconds for retrying failed installations

# Arrays to track installation status
success_apps=()
failed_apps=()
rollback_apps=()
app_times=()
retries_failed=()

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
  # Validate required keys in configuration file
  REQUIRED_KEYS=("REQUIRED_VERSION" "MAX_RETRIES" "RETRY_DELAY")
  for key in "${REQUIRED_KEYS[@]}"; do
    if [ -z "${!key}" ]; then
      echo "Error: Missing required configuration key '$key' in $CONFIG_FILE. Exiting."
      exit 1
    fi
  done
else
  echo "Configuration file not found. Exiting."
  exit 1
fi

# Function to print colored messages
print_message() {
  local color=$1
  local message=$2
  if [ "$VERBOSE_MODE" = true ]; then
    case $color in
      green) echo -e "\033[0;32m$message\033[0m" | tee -a "$LOG_FILE" ;;
      yellow) echo -e "\033[0;33m$message\033[0m" | tee -a "$LOG_FILE" ;;
      red) echo -e "\033[0;31m$message\033[0m" | tee -a "$LOG_FILE" ;;
      *) echo "$message" | tee -a "$LOG_FILE" ;;
    esac
  fi
}

# Function to notify user
notify_user() {
  if command_exists "$NOTIFY_SUCCESS"; then
    "$NOTIFY_SUCCESS" "$1" "$2"
  fi
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to check internet connectivity
check_internet() {
  local endpoints=("google.com" "cloudflare.com" "github.com" "192.168.1.1")
  for endpoint in "${endpoints[@]}"; do
    if ping -c 1 "$endpoint" &>/dev/null; then
      print_message green "Internet connection detected through $endpoint."
      return
    fi
    if curl -Is "$endpoint" &>/dev/null; then
      print_message green "Internet connection verified using curl with $endpoint."
      return
    fi
    if wget --spider "$endpoint" &>/dev/null; then
      print_message green "Internet connection verified using wget with $endpoint."
      return
    fi
  done
  print_message red "No internet connection detected using ping, curl, or wget. Please check your connection and try again."
  exit 1
}

# Function to retry commands with delay
retry() {
  local n=1
  local command="$@"
  until [ $n -ge $((MAX_RETRIES + 1)) ]; do
    print_message yellow "Attempt $n: $command"
    $command && return 0
    n=$((n + 1))
    print_message red "Retry $n failed for: $command"
    sleep $RETRY_DELAY
  done
  return 1
}

# Function to track execution time
track_time() {
  local start_time=$(date +%s)
  if ! $1; then
    print_message red "Error: Command $1 failed during execution."
    return 1
  fi
  local end_time=$(date +%s)
  local elapsed_time=$((end_time - start_time))
  app_times+=("$2: ${elapsed_time}s")
}

# Function to check for macOS updates
check_macos_updates() {
  print_message yellow "Checking for macOS updates..."
  if softwareupdate -l | grep -q "\* Label:"; then
    print_message yellow "Updates are available. Installing updates..."
    if retry sudo softwareupdate -ia --verbose; then
      print_message green "macOS updates installed successfully."
    else
      print_message red "Failed to install macOS updates. Exiting."
      exit 1
    fi
  else
    print_message green "macOS is up to date."
  fi
}

# Function to validate macOS version
validate_macos_version() {
  local current_version=$(sw_vers -productVersion)
  if [[ "$current_version" < "$REQUIRED_VERSION" ]]; then
    print_message red "This script requires macOS $REQUIRED_VERSION or later. Current version: $current_version."
    read -p "Do you want to continue anyway? (yes/no): " choice
    [[ "$choice" != "yes" ]] && exit 1
  fi
  print_message green "macOS version validated: $current_version."
}

# Function to check system performance
check_system_performance() {
  local cpu_usage=$(ps -A -o %cpu | awk '{s+=$1} END {print s}')
  local ram_free=$(vm_stat | grep "free:" | awk '{print $3}' | sed 's/\.//')
  local ram_free_mb=$((ram_free * 4096 / 1024 / 1024))

  if (( $(echo "$cpu_usage > 80" | bc -l) )); then
    print_message red "High CPU usage detected: ${cpu_usage}%"
    read -p "Do you want to continue? (yes/no): " choice
    [[ "$choice" != "yes" ]] && exit 1
  fi

  if (( ram_free_mb < 1024 )); then
    print_message red "Low free RAM detected: ${ram_free_mb} MB"
    read -p "Do you want to continue? (yes/no): " choice
    [[ "$choice" != "yes" ]] && exit 1
  fi

  print_message green "System performance is sufficient."
}

# Function to check disk space
check_disk_space() {
  local available_space=$(df / | tail -1 | awk '{print $4}')
  if (( available_space < REQUIRED_SPACE )); then
    print_message red "Insufficient disk space. At least 10GB is required."
    exit 1
  fi
  local available_gb=$((available_space / 1024 / 1024))
  print_message green "Available disk space: ${available_gb} GB"
}

# Function to check and install dependencies
check_dependencies() {
  local dependencies=(brew xcode-select curl)
  for dep in "${dependencies[@]}"; do
    if ! command_exists $dep; then
      print_message yellow "$dep is not installed. Installing..."
      retry sudo brew install $dep || {
        print_message red "Failed to install $dep. Please check your internet connection and Homebrew configuration. Detailed logs available in $LOG_FILE. Exiting."
        echo "Dependency installation failed: $dep" >> "$LOG_FILE"
        exit 1
      }
    else
      print_message green "$dep is already installed."
    fi
  done
}

# Rollback function
rollback_installations() {
  if [ ${#rollback_apps[@]} -gt 0 ]; then
    print_message yellow "Rolling back installed applications..."
    for app in "${rollback_apps[@]}"; do
      local app_state
      app_state=$(brew info --json=v1 "$app" 2>/dev/null | jq -r '.[0].installed | length')
      if [ "$app_state" -gt 0 ]; then
        print_message red "Rolling back $app due to installation failure."
        retry sudo brew uninstall --force "$app" | tee -a "$LOG_FILE"
        print_message yellow "Rolled back: $app"
      else
        print_message yellow "$app was not fully installed or already removed. Skipping rollback."
      fi
    done
  fi
}

# Function to auto-restart failed installations
retry_failed_installations() {
  if [ ${#failed_apps[@]} -gt 0 ]; then
    print_message yellow "Retrying failed installations after a cooldown of $COOLDOWN_PERIOD seconds..."
    sleep $COOLDOWN_PERIOD
    retries_failed=()
    for app in "${failed_apps[@]}"; do
      print_message yellow "Retrying installation for: $app"
      install_or_upgrade "$app" && retries_failed+=("$app")
    done
    if [ ${#retries_failed[@]} -gt 0 ]; then
      print_message red "Failed again for the following apps:"
      for failed_app in "${retries_failed[@]}"; do
        print_message red "- $failed_app"
      done
    else
      print_message green "All previously failed installations were successfully retried."
    fi
  fi
}

# Function to install or upgrade applications
install_or_upgrade() {
  local app=$1
  local is_cask=$2

  if [ "$DRY_RUN" = true ]; then
    print_message yellow "Dry run: Would install $app (Cask: $is_cask)"
    return 0
  fi

  if [ "$is_cask" = true ]; then
    retry sudo brew install --cask "$app" && success_apps+=("$app") || {
      failed_apps+=("$app"); rollback_apps+=("$app");
    }
  else
    retry sudo brew install "$app" && success_apps+=("$app") || {
      failed_apps+=("$app"); rollback_apps+=("$app");
    }
  fi
}

# Graceful exit handling
trap "{
  print_message red 'Script interrupted. Cleaning up...';
  rollback_installations;
  print_message yellow 'Cleaning logs and temporary files...';
  echo 'Script interrupted by the user.' >> "$LOG_FILE";
  exit 1;
}" INT TERM

# Main script execution
main() {
  print_message green "Starting macOS setup script..."

  # Check internet connectivity
  check_internet

  # Check for macOS updates
  check_macos_updates

  # Validate macOS version
  validate_macos_version

  # Check system performance
  check_system_performance

  # Check disk space
  check_disk_space

  # Check dependencies
  check_dependencies

  # Install applications
  apps=(
    "cleanmymac-x:true"
    "iterm2:true"
    "python:false"
    "wget:false"
    "microsoft-teams:true"
    "onedrive:false"
    "insomnia:true"
    "whatsapp:true"
    "xmind:true"
    "the-unarchiver:true"
    "spotify:true"
    "vlc:true"
    "google-chrome:true"
    "visual-studio-code:true"
    "git:false"
    "github:true"
    "docker:true"
    #"chatgpt:true"
  )

  total_apps=${#apps[@]}
  current_app=0

  for app_entry in "${apps[@]}"; do
    app_name=$(echo "$app_entry" | cut -d":" -f1)
    is_cask=$(echo "$app_entry" | cut -d":" -f2)
    current_app=$((current_app + 1))

    progress=$((current_app * 100 / total_apps))
    print_message green "Installing [$current_app/$total_apps] ($progress%): $app_name"
    install_or_upgrade "$app_name" "$is_cask"
  done

  # Final summary
  if [ ${#failed_apps[@]} -gt 0 ]; then
    print_message red "Failed to install the following applications:"
    for app in "${failed_apps[@]}"; do
      print_message red "- $app"
    done
    retry_failed_installations
  else
    print_message green "All applications installed successfully."
    notify_user "Setup Complete" "All applications installed successfully."
  fi

  print_message green "Cleaning up..."
  sudo brew cleanup >/dev/null 2>&1
}

# Run the main function
main
