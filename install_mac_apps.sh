#!/bin/bash

# Configuration file path
CONFIG_FILE="config.txt"

# Log file for installation process
LOG_FILE="install_log.json"
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
MAX_PARALLEL_JOBS=${MAX_PARALLEL_JOBS:-4} # Limit parallel execution

# Arrays to track installation status
success_apps=()
failed_apps=()
rollback_apps=()
app_times=()
retries_failed=()
current_jobs=0

# Helper function to add timestamps to logs
log_with_timestamp() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to write logs in JSON format
log_to_json() {
  local type=$1
  local message=$2
  echo "{\"timestamp\": \"$(date +'%Y-%m-%d %H:%M:%S')\", \"type\": \"$type\", \"message\": \"$message\"}" >> "$LOG_FILE"
}

# Function to print colored messages
print_message() {
  local color=$1
  local message=$2
  if [ "$VERBOSE_MODE" = true ]; then
    case $color in
      green) log_to_json "info" "$message" ;;
      yellow) log_to_json "warning" "$message" ;;
      red) log_to_json "error" "$message" ;;
      *) log_to_json "info" "$message" ;;
    esac
  fi
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to check, install, and update dependencies
check_and_update_dependencies() {
  local dependencies=(xcode-select brew curl)

  for dep in "${dependencies[@]}"; do
    if ! command_exists "$dep"; then
      print_message yellow "$dep is not installed. Installing..."
      if [ "$dep" = "xcode-select" ]; then
        xcode-select --install || {
          print_message red "Failed to install xcode-select. Exiting."
          exit 1
        }
      elif [ "$dep" = "brew" ]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
          print_message red "Failed to install Homebrew. Exiting."
          exit 1
        }
      elif [ "$dep" = "curl" ]; then
        retry_with_backoff $MAX_RETRIES sudo brew install curl || {
          print_message red "Failed to install curl. Exiting."
          exit 1
        }
      fi
    else
      print_message green "$dep is already installed."
      if [ "$dep" = "brew" ]; then
        print_message green "Updating Homebrew..."
        retry_with_backoff $MAX_RETRIES brew update || {
          print_message red "Failed to update Homebrew. Exiting."
          exit 1
        }
      fi
    fi
  done
}

# System resource checks
check_system_resources() {
  local available_space=$(df / | tail -1 | awk '{print $4}')
  if (( available_space < REQUIRED_SPACE )); then
    print_message red "Insufficient disk space. At least 10GB is required."
    exit 1
  fi
  print_message green "Sufficient disk space detected."

  local cpu_usage=$(ps -A -o %cpu | awk '{s+=$1} END {print s}')
  if (( $(echo "$cpu_usage > 80" | bc -l) )); then
    print_message red "High CPU usage detected: ${cpu_usage}%"
    exit 1
  fi
  print_message green "CPU usage is within acceptable limits."
}

# Function to retry commands with exponential backoff
retry_with_backoff() {
  local attempt=1
  local max_attempts=$1
  shift
  local command="$@"

  while [ $attempt -le $max_attempts ]; do
    print_message yellow "Attempt $attempt: $command"
    $command && return 0
    sleep $((RETRY_DELAY * 2 ** (attempt - 1)))
    attempt=$((attempt + 1))
  done
  print_message red "All retry attempts failed: $command"
  return 1
}

# Dry run simulation
simulate_installation() {
  local app=$1
  print_message yellow "[Dry Run] Simulating installation of $app."
}

# Install or upgrade applications
install_or_upgrade_app() {
  local app=$1
  local is_cask=$2

  local start_time=$(date +%s)

  if [ "$DRY_RUN" = true ]; then
    simulate_installation "$app"
    return 0
  fi

  if [ "$is_cask" = true ]; then
    retry_with_backoff $MAX_RETRIES sudo brew install --cask "$app" && success_apps+=("$app") || {
      failed_apps+=("$app")
      rollback_apps+=("$app")
    }
  else
    retry_with_backoff $MAX_RETRIES sudo brew install "$app" && success_apps+=("$app") || {
      failed_apps+=("$app")
      rollback_apps+=("$app")
    }
  fi

  local end_time=$(date +%s)
  local elapsed_time=$((end_time - start_time))
  app_times+=("$app:$elapsed_time seconds")
}

# Rollback failed installations
rollback_failed_installations() {
  for app in "${rollback_apps[@]}"; do
    print_message yellow "Rolling back installation of: $app"
    sudo brew uninstall "$app" >/dev/null 2>&1
  done
  rollback_apps=()
}

# Display user feedback
summary_feedback() {
  print_message green "Installation Summary:"
  print_message green "Successfully installed applications:"
  for app in "${success_apps[@]}"; do
    print_message green "- $app"
  done

  if [ ${#failed_apps[@]} -gt 0 ]; then
    print_message red "Failed to install applications:"
    for app in "${failed_apps[@]}"; do
      print_message red "- $app"
    done
    rollback_failed_installations
  else
    print_message green "All applications installed successfully."
  fi

  print_message green "Performance Metrics:"
  for app_time in "${app_times[@]}"; do
    print_message green "$app_time"
  done
}

# Environment check
check_environment() {
  if [[ "$OSTYPE" != "darwin"* ]]; then
    print_message red "This script is designed to run on macOS. Exiting."
    exit 1
  fi

  local current_version=$(sw_vers -productVersion)
  if [[ "$current_version" < "$REQUIRED_VERSION" ]]; then
    print_message yellow "Your macOS version ($current_version) is below the required version ($REQUIRED_VERSION)."
    read -p "Do you want to continue anyway? (yes/no): " user_choice
    if [[ "$user_choice" != "yes" ]]; then
      print_message red "Exiting script due to unsupported macOS version."
      exit 1
    fi
  fi

  print_message green "Checking for macOS updates..."
  if softwareupdate -l | grep -q "\* Label:"; then
    print_message yellow "Updates are available. Installing updates..."
    retry_with_backoff $MAX_RETRIES sudo softwareupdate -ia --verbose || {
      print_message red "Failed to install macOS updates. Exiting."
      exit 1
    }
    print_message green "macOS updates installed successfully."
  else
    print_message green "macOS is up to date."
  fi

  print_message green "Environment check passed. Running on macOS version $current_version."
}

# Load dynamic configuration
load_configuration() {
  if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    print_message green "Configuration loaded from $CONFIG_FILE."
  else
    print_message yellow "Configuration file not found. Using default values."
  fi
}

# Job queue to manage parallel execution
manage_jobs() {
  while (( current_jobs >= MAX_PARALLEL_JOBS )); do
    wait -n
    current_jobs=$((current_jobs - 1))
  done
  current_jobs=$((current_jobs + 1))
}

# Main function
main() {
  print_message green "Starting macOS setup script..."

  # Check and update dependencies
  check_and_update_dependencies

  # Environment check
  check_environment

  # Load configuration
  load_configuration

  # Check system resources
  check_system_resources

  # Define applications to install
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
  )

  # Install applications
  for app_entry in "${apps[@]}"; do
    manage_jobs
    local app_name=$(echo "$app_entry" | cut -d":" -f1)
    local is_cask=$(echo "$app_entry" | cut -d":" -f2)
    print_message green "Installing: $app_name"
    install_or_upgrade_app "$app_name" "$is_cask" &
  done

  # Wait for all background processes to finish
  wait

  # Provide feedback
  summary_feedback

  print_message green "Cleaning up..."
  sudo brew cleanup >/dev/null 2>&1
}

# Run the main function
main
