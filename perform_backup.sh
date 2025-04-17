#!/bin/bash

# ===============================================================================
# Script Name:   MEGA Backup Script
# Description:   Compressed backup to multiple MEGA volumes with space management
# Author:        Natan Gallo, chatGPT, DeepSeek
# Created:       2024-01-10
# ===============================================================================
# Version |    Date    | Author      | Description
# --------|------------|-------------|-------------------------------------------
# 1.0     | 2024-03-08 | Natan Gallo | Initial release
# 2.0     | 2024-03-10 | Natan Gallo | added debug and production mode
# 3.0     | 2024-03-10 | Natan Gallo | Implemented chunk creation
# 3.1     | 2024-03-12 | Natan Gallo | Added duplicate file management
# ===============================================================================

###############################################################################
#                          CONFIGURATION SETTINGS                             #
###############################################################################

# Debug mode (0=disabled, 1=enabled)
DEBUG=0

# Production mode (0=dry-run, 1=real operations)
PRODUCTION=1

# Minimum free space threshold (10MB in bytes)
block_min_size=10485760

# Split chunk size (default 1GB, adjust as needed)
split_chunk_size=$((1024 * 1024 * 1024))

# External scripts paths
CHECK_SESSION_SCRIPT="./check_session.sh"
NOTIFY_SCRIPT="./notify.sh"

# Backup sources (modify as needed)
sources=(
  "/your/source/folder"
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

# Split and transfer large file across multiple volumes
split_and_transfer() {
  local source="$1"
  local tmpfile="$2"
  local filesize="$3"
  
  local remaining=$filesize
  local part_number=1
  local transferred=0
  
  while (( remaining > 0 && curr_vol_index < ${#volumes[@]} )); do
    current_volume="${volumes[$curr_vol_index]}"
    free_space=$(get_free_space "$current_volume")
    
    if (( free_space < block_min_size )); then
      debug_log "Volume full, moving to next"
      ((curr_vol_index++))
      continue
    fi

    # Calculate chunk size (smaller of remaining space or split_chunk_size)
    local chunk_size=$(( free_space > split_chunk_size ? split_chunk_size : free_space ))
    chunk_size=$(( chunk_size > remaining ? remaining : chunk_size ))
    
    local part_file="${tmpfile}.part${part_number}"
    local dest_path="${current_volume}/$(basename "$source")_backup.part${part_number}.tar.gz"
    
    debug_log "Creating split part $part_number (${chunk_size} bytes) for $source"
    
    # Split the file
    if ! run_command "dd if='$tmpfile' of='$part_file' bs=1 count=$chunk_size skip=$transferred 2>/dev/null"; then
      error_log "Failed to split file for '$source'"
      safe_remove "$part_file"
      return 1
    fi

    # Transfer the chunk
    debug_log "Transferring part $part_number to $current_volume"
    if ! run_command "mega-put '$part_file' '$dest_path'"; then
      error_log "Failed to transfer part $part_number of '$source'"
      safe_remove "$part_file"
      return 1
    fi

    safe_remove "$part_file"
    
    transferred=$((transferred + chunk_size))
    remaining=$((filesize - transferred))
    ((part_number++))
    
    # If we've transferred everything, break the loop
    if (( remaining <= 0 )); then
      break
    fi
    
    # Move to next volume if current is full
    if (( $(get_free_space "$current_volume") < block_min_size )); then
      ((curr_vol_index++))
    fi
  done

  if (( remaining > 0 )); then
    error_log "Failed to transfer all parts of '$source' (${remaining} bytes remaining)"
    return 1
  fi

  return 0
}

# Compress and transfer source to specified volume
compress_and_transfer() {
  local source="$1"
  local volume="$2"
  local backup_name="backup_$(basename "$source").tar.gz"
  local tmpfile="$TMP_DIR/backup_temp_$(basename "$source").tar.gz"
  
  # 1. Check and clean existing backups
  debug_log "Checking for existing backups of '$backup_name'"
  for v in "${volumes[@]}"; do
    if run_command "mega-find \"$v/$backup_name\"" | grep -q "$backup_name"; then
      debug_log "Found existing backup on $v - removing..."
      run_command "mega-rm \"$v/$backup_name\""
    fi
  done

  # 2. Check local disk space
  local source_size=$(du -sb "$source" | awk '{print $1}')
  local local_free=$(df -B1 "$TMP_DIR" | awk 'NR==2 {print $4}')
  
  if (( source_size > local_free )); then
    debug_log "Not enough local disk space ($(format_number $local_free) for source ($(format_number $source_size))"
    return 1
  fi

  # 3. Compress source
  debug_log "Compressing '$source'..."
  if ! run_command "tar -czf \"$tmpfile\" \"$source\""; then
    error_log "Compression failed for '$source'"
    safe_remove "$tmpfile"
    return 1
  fi

  local filesize=$(stat -c%s "$tmpfile")
  local free_space=$(get_free_space "$volume")
  
  debug_log "$(basename "$source") - Size: $(format_number $filesize) - Needed: $(format_number $free_space)"

  # 4. Handle file transfer
  if (( filesize > free_space )); then
    debug_log "File too large for single volume, splitting across volumes..."
    if split_and_transfer "$source" "$tmpfile" "$filesize"; then
      safe_remove "$tmpfile"
      return 0
    else
      safe_remove "$tmpfile"
      return 1
    fi
  fi
  
  # 5. Standard transfer
  debug_log "Transferring '$tmpfile' to '$volume'"
  if [[ "$tmpfile" == *" "* ]] || [[ "$volume" == *" "* ]]; then
    error_log "Spaces in paths not supported: '$tmpfile' or '$volume'"
    return 1
  fi
  
  if ! run_command "mega-put '$tmpfile' '$volume/$backup_name'"; then
    error_log "Transfer failed for '$source'"
    safe_remove "$tmpfile"
    
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
  [ -n "$NOTIFY_SCRIPT" ] && $NOTIFY_SCRIPT "SUCCESS: Backup on MegaDrive failed: $1"
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
[ -n "$NOTIFY_SCRIPT" ] && run_command "\"$NOTIFY_SCRIPT\" \"SUCCESS: Backup on MegaDrive, completed successfully\""
exit 0
