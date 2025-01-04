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

# Internet connectivity check
check_internet_connectivity() {
  local fallback_url="https://www.cloudflare.com/"
  if command_exists "curl"; then
    curl -s https://www.google.com > /dev/null || curl -s "$fallback_url" > /dev/null
  elif command_exists "wget"; then
    wget -q --spider https://www.google.com || wget -q --spider "$fallback_url"
  elif command_exists "ping"; then
    ping -c 1 google.com &>/dev/null || ping -c 1 example.com &>/dev/null
  else
    print_message red "No valid network checking tool is installed. Please install curl, wget, or ensure ping is available."
    exit 1
  fi

  if [ $? -ne 0 ]; then
    print_message red "No internet connection. Please check your network."
    exit 1
  fi

  print_message green "Internet connection is active."
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to check, install, and update xcode-select
check_xcode_select() {
  if ! command_exists "xcode-select"; then
    print_message yellow "xcode-select is not installed. Installing..."
    xcode-select --install || {
      print_message red "Failed to install xcode-select. Exiting."
      exit 1
    }
  else
    print_message green "xcode-select is already installed."
  fi
}

# Function to check, install, and update Homebrew
check_brew() {
  if ! command_exists "brew"; then
    print_message yellow "Homebrew is not installed. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
      print_message red "Failed to install Homebrew. Exiting."
      exit 1
    }
  else
    print_message green "Homebrew is already installed. Updating..."
    retry_with_backoff $MAX_RETRIES brew update || {
      print_message red "Failed to update Homebrew. Exiting."
      exit 1
    }
  fi
}

# Function to check, install, and update curl
check_curl() {
  if ! command_exists "curl"; then
    print_message yellow "curl is not installed. Installing..."
    retry_with_backoff $MAX_RETRIES sudo brew install curl || {
      print_message red "Failed to install curl. Exiting."
      exit 1
    }
  else
    print_message green "curl is already installed."
  fi
}

# Function to check and update all dependencies
check_and_update_dependencies() {
  check_xcode_select
  check_brew
  check_curl
}

# System resource checks
check_system_resources() {
  local available_space
  available_space=$(df --output=avail / 2>/dev/null | tail -1)
  if [[ -z "$available_space" ]] || ! [[ "$available_space" =~ ^[0-9]+$ ]]; then
    print_message red "Failed to retrieve available disk space. Ensure 'df' is functioning correctly."
    exit 1
  fi

  if (( available_space < REQUIRED_SPACE )); then
    print_message red "Insufficient disk space. At least 10GB is required."
    exit 1
  fi
  print_message green "Sufficient disk space detected."

  local cpu_usage
  local mem_free
  cpu_usage=$(ps -A -o %cpu | awk '{s+=$1} END {print s}')
  mem_free=$(vm_stat | awk '/Pages free/ {print $3}' | sed 's/\.//')
  local mem_free_mb=$((mem_free * 4096 / 1024 / 1024))

  if (( $(echo "$cpu_usage > 80" | bc -l) )); then
    print_message red "High CPU usage detected: ${cpu_usage}%"
    exit 1
  fi

  if (( mem_free_mb < 512 )); then
    print_message red "Low memory detected: ${mem_free_mb}MB free."
    exit 1
  fi

  print_message green "CPU usage and memory are within acceptable limits."
}

# Retry logic with dynamic delays
retry_with_backoff() {
  local attempt=1
  local max_attempts=$1
  shift
  local command="$@"

  while [ $attempt -le $max_attempts ]; do
    local delay=$((RETRY_DELAY * attempt + RANDOM % 5))
    print_message yellow "Attempt $attempt: $command (Retry in $delay seconds)"
    $command 2>>"$LOG_FILE" && return 0
    sleep $delay
    attempt=$((attempt + 1))
  done
  print_message red "All retry attempts failed: $command"
  return 1
}

# Fail-safe mechanism
setup_fail_safe() {
  trap "print_message red 'Script terminated unexpectedly. Cleaning up...'; exit 1" SIGINT SIGTERM
}

# Parallel execution setup
manage_jobs() {
  while (( current_jobs >= MAX_PARALLEL_JOBS )); do
    wait -n
    current_jobs=$((current_jobs - 1))
  done
  current_jobs=$((current_jobs + 1))
}

# Dry run simulation
simulate_installation() {
  local app=$1
  print_message yellow "[Dry Run] Simulating installation of $app."
}

# Load applications from configuration file
load_apps_from_config() {
  if [ -f "$CONFIG_FILE" ]; then
    apps=($(grep -v '^#' "$CONFIG_FILE" | grep -v '^$'))
    print_message green "Applications loaded from configuration file: ${apps[@]}"
  else
    print_message red "Configuration file not found. Exiting."
    exit 1
  fi
}

# Install or upgrade applications
install_or_upgrade_app() {
  local app=$1
  local is_cask=$2

  # Validate is_cask input
  if [[ "$is_cask" != true && "$is_cask" != false ]]; then
    print_message red "Invalid value for is_cask: $is_cask. Must be 'true' or 'false'. Exiting."
    exit 1
  fi

  local start_time=$(date +%s)

  if [ "$DRY_RUN" = true ]; then
    simulate_installation "$app"
    return 0
  fi

  if [ "$is_cask" = true ]; then
    retry_with_backoff $MAX_RETRIES sudo brew install --cask "$app" && success_apps+=("$app") || {
      print_message red "Installation of $app failed. See $LOG_FILE for details."
      failed_apps+=("$app")
      rollback_apps+=("$app")
    }
  else
    retry_with_backoff $MAX_RETRIES sudo brew install "$app" && success_apps+=("$app") || {
      print_message red "Installation of $app failed. See $LOG_FILE for details."
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

# Main function
main() {
  print_message green "Starting macOS setup script..."

  # Setup fail-safe mechanism
  setup_fail_safe

  # Check internet connectivity
  check_internet_connectivity

  # Check and update dependencies
  check_and_update_dependencies

  # Load applications from configuration file
  load_apps_from_config

  # System resource checks
  check_system_resources

  # Install applications
  for app_entry in "${apps[@]}"; do
    manage_jobs
    print_message green "Installing: $app_entry"
    install_or_upgrade_app "$app_entry" false &
  done

  # Wait for all background jobs to complete
  wait

  # Display installation summary
  summary_feedback
}

# Run the main function
main
