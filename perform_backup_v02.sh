#!/bin/bash
# ======================================================================
# MEGA Backup Script
# Purpose: Compressed backup to multiple MEGA volumes with space management
# Version: 2.0
# Created: 2023-11-20
# Author: Natan Gallo, DeepSeek Agent
# ======================================================================

###############################################################################
#                          CONFIGURATION SETTINGS                             #
###############################################################################

# Debug mode (0=disabled, 1=enabled)
DEBUG=1

# Production mode (0=dry-run, 1=real operations)
PRODUCTION=1

# Minimum free space threshold (10MB in bytes)
block_min_size=10485760

# External scripts paths
CHECK_SESSION_SCRIPT="./check_session.sh"
NOTIFY_SCRIPT="./notify.sh"

# Backup sources (modify as needed)
sources=(
  "/home/remote_server/mega-bkp"
# "/path/to/source2"
  # Add more paths if needed
)

###############################################################################
#                          GLOBAL VARIABLES                                   #
###############################################################################

# Array of available MEGA volumes (will be populated dynamically)
volumes=()

# Current volume index
curr_vol_index=0

# Temporary directory for compressed files
TMP_DIR="/tmp"

###############################################################################
#                          MAIN FUNCTIONS                                     #
###############################################################################

# Initialize available MEGA volumes
init_volumes() {
  debug_log "Searching for available MEGA volumes..."
  
  while IFS= read -r line; do
    if [[ $line == "INSHARE on "* ]]; then
      volume_path=$(echo "$line" | awk '{print $3}')
      volumes+=("$volume_path")
      debug_log "Found volume: $volume_path"
    fi
  done < <(mega-mount 2>/dev/null)

  if [ ${#volumes[@]} -eq 0 ]; then
    error_exit "No MEGA volumes found"
  fi

  debug_log "Available volumes: ${volumes[*]}"
}

# Get free space on specified volume
get_free_space() {
  local volume="$1"
  local total_space=53687091200  # 50GB in bytes
  local used_space=0
  local free_space=0
  local volume_name=""

  # Map volume paths to mega-df display names
  case "$volume" in
    "//") volume_name="Cloud drive" ;;
    "//in") volume_name="Inbox" ;;
    "//bin") volume_name="Rubbish bin" ;;
    *) volume_name="${volume##*:}" ;;  # Extract INSHARE name
  esac

  debug_log "Calculating space for '$volume' (mapped to: '$volume_name')"

  local df_output=$(mega-df 2>/dev/null)
  
  if [[ "$volume_name" == "Cloud drive" ]]; then
    used_space=$(echo "$df_output" | awk -F: '/USED STORAGE:/ {print $2}' | awk '{print $1}')
    free_space=$((total_space - used_space))
  else
    local volume_line=""
    if [[ "$volume_name" == "Inbox" || "$volume_name" == "Rubbish bin" ]]; then
      volume_line=$(echo "$df_output" | grep -E "^${volume_name}:")
    else
      volume_line=$(echo "$df_output" | grep -E "^ ${volume_name}:")
    fi

    if [ -z "$volume_line" ]; then
      debug_log "Volume '$volume_name' not found!"
      echo 0
      return 1
    fi

    used_space=$(echo "$volume_line" | awk '{print $2}')
    free_space=$((total_space - used_space))
  fi

  debug_log "$volume_name - Used: $(format_number $used_space) - Free: $(format_number $free_space)"
  echo "$free_space"
}

# Compress and transfer source to specified volume
compress_and_transfer() {
  local source="$1"
  local volume="$2"
  local tmpfile="$TMP_DIR/backup_temp_$(basename "$source").tar.gz"
  
  # Check local disk space
  local source_size=$(du -sb "$source" | awk '{print $1}')
  local local_free=$(df -B1 "$TMP_DIR" | awk 'NR==2 {print $4}')
  
  if (( source_size > local_free )); then
    debug_log "Not enough local disk space ($(format_number $local_free) for source ($(format_number $source_size))"
    return 1
  fi

  debug_log "Compressing '$source'..."
  
  if ! run_command "tar -czf \"$tmpfile\" \"$source\""; then
    error_log "Compression failed for '$source'"
    safe_remove "$tmpfile"
    return 1
  fi

  local filesize=$(stat -c%s "$tmpfile")
  local free_space=$(get_free_space "$volume")
  
  debug_log "$(basename "$source") - Size: $(format_number $filesize) - Needed: $(format_number $free_space)"

  if (( filesize > free_space )); then
    debug_log "Not enough space on '$volume'"
    safe_remove "$tmpfile"
    return 1
  fi
  
  debug_log "Transferring '$tmpfile' to '$volume'"
  
  # controllo degli spazi nei percorsi
  if [[ "$tmpfile" == *" "* ]] || [[ "$volume" == *" "* ]]; then
    error_log "Spazi nei percorsi non supportati: '$tmpfile' o '$volume'"
    return 1
  fi
  
  if ! run_command "mega-put '$tmpfile' '$volume/$(basename "$source")_backup.tar.gz'"; then
#  if ! run_command "mega-put \"$tmpfile\" \"$volume/$(basename \"$source\")_backup.tar.gz\""; then
    error_log "Transfer failed for '$source'"
    safe_remove "$tmpfile"
    
    # Check if failure was due to full volume
    if (( $(get_free_space "$volume") < block_min_size )); then
      debug_log "Volume filled during transfer, trying next volume"
      return 2
    fi
    
    return 1
  fi

  safe_remove "$tmpfile"
  return 0
}

###############################################################################
#                          HELPER FUNCTIONS                                   #
###############################################################################

# Debug logging
debug_log() {
  [ "$DEBUG" = "1" ] && echo "DEBUG: $1" >&2
}

# Error logging
error_log() {
  echo "ERROR: $1" >&2
}

# Critical error handling
error_exit() {
  error_log "$1"
  [ -n "$NOTIFY_SCRIPT" ] && $NOTIFY_SCRIPT "Backup failed: $1"
  exit 1
}

# Format numbers with thousands separator
format_number() {
  printf "%'d" "$1"
}

# Run command based on PRODUCTION mode
run_command() {
    local cmd="$1"
    if [ "$PRODUCTION" = "1" ]; then
        debug_log "EXECUTING: $cmd"
        eval "$cmd"
    else
        debug_log "DRY-RUN: Would execute: $cmd"
        return 0
    fi
}

# Safe file removal
safe_remove() {
  if [ "$PRODUCTION" = "1" ]; then
    rm -f "$1" 2>/dev/null
  else
    debug_log "DRY-RUN: Would remove: $1"
  fi
}

# Adjust debug mode if in dry-run
adjust_debug_mode() {
  if [ "$PRODUCTION" = "0" ] && [ "$DEBUG" = "0" ]; then
    DEBUG=1
    debug_log "Auto-enabled DEBUG mode for dry-run"
  fi
}

###############################################################################
#                          SESSION VERIFICATION                               #
###############################################################################

# Check MEGA session with detailed error handling
debug_log "Verifying MEGA session..."
check_session_output=$("$CHECK_SESSION_SCRIPT" 2>&1)
check_session_result=$?

case $check_session_result in
    0) debug_log "Session active: $(echo "$check_session_output" | grep 'Account e-mail:')" ;;
    1) error_exit "Session expired - $check_session_output" ;;
    2) error_exit "Session check failed - $check_session_output" ;;
    3) error_exit "Unrecognized session status - $check_session_output" ;;
    *) error_exit "Unknown error during session check" ;;
esac

###############################################################################
#                          MAIN EXECUTION                                     #
###############################################################################

# Adjust debug mode if needed
adjust_debug_mode

# Verify MEGA session
[ -x "$CHECK_SESSION_SCRIPT" ] || error_exit "Session check script not found"
run_command "\"$CHECK_SESSION_SCRIPT\"" || error_exit "Session check failed"

# Initialize available volumes
init_volumes

# Process each source
for src in "${sources[@]}"; do
  debug_log "Processing source: '$src'"
  
  while (( curr_vol_index < ${#volumes[@]} )); do
    current_volume="${volumes[$curr_vol_index]}"
    free_space=$(get_free_space "$current_volume")
    
    debug_log "Volume '$current_volume' - Free space: $(format_number $free_space)"

    if (( free_space < block_min_size )); then
      debug_log "Volume full, moving to next"
      ((curr_vol_index++))
      continue
    fi

    compress_and_transfer "$src" "$current_volume"
    transfer_result=$?
    
    if (( transfer_result == 0 )); then
      debug_log "Backup completed successfully"
      break
    elif (( transfer_result == 2 )); then
      # Volume filled during transfer, try next
      ((curr_vol_index++))
    else
      # Other error, move to next volume
      ((curr_vol_index++))
    fi
  done

  if (( curr_vol_index >= ${#volumes[@]} )); then
    error_exit "All volumes are full. Backup aborted."
  fi
done

debug_log "Backup completed successfully"
[ -n "$NOTIFY_SCRIPT" ] && run_command "\"$NOTIFY_SCRIPT\" \"Backup completed successfully\""
exit 0
