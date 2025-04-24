#!/bin/bash

# ===============================================================================
# Script Name:   MEGA Backup Script (Proxmox Optimized)
# Description:   Handles Proxmox backups (.vma.gz, .tar.zst) and regular files
#                with smart compression, multi-volume splitting, and space management
# Author:        Natan Gallo, ChatGPT, DeepSeek
# Created:       2024-01-10
# Last Modified: 2024-04-20
# ===============================================================================
# Version |    Date    | Author      | Description
# --------|------------|-------------|-------------------------------------------
# 1.0     | 2025-03-08 | Natan Gallo | Initial release
# 2.0     | 2025-03-10 | Natan Gallo | added debug and production mode
# 3.0     | 2025-03-10 | Natan Gallo | Implemented chunk creation
# 3.1     | 2025-03-12 | Natan Gallo | Added duplicate file management
# 3.2     | 2025-04-17 | Natan Gallo | File-by-file processing for directories
# 3.3     | 2025-04-24 | Natan Gallo | Handle compressed and uncompressed files
# 4.0     | 2024-04-24 | Natan Gallo | Proxmox-optimized, dual-mode compression
#         |            |             | Improved logging and volume management
# ===============================================================================

###############################################################################
#                          CONFIGURATION SETTINGS                             #
###############################################################################

# Operation Modes
DEBUG=0                  # 0=disabled, 1=enabled
PRODUCTION=1             # 0=dry-run, 1=real operations

# Space Management
MIN_FREE_SPACE=$((10 * 1024 * 1024))  # 10MB minimum
CHUNK_SIZE=$((1 * 1024 * 1024 * 1024)) # 1GB chunks

# Proxmox Backup Formats (skip compression)
COMPRESSED_FORMATS=("vma.gz" "tar.zst" "tar.gz" "zst" "gz" "xz" "bz2")

# Paths
TMP_DIR="/tmp/mega_backup"
LOG_FILE="/var/log/mega_backup.log"

# Backup sources (modify these paths)
SOURCES=(
	"/home/remote_server/mega-bkp"	# This Script folder
	"/var/lib/usb/dump"				# Proxmox Dump files
)

###############################################################################
#                          CORE FUNCTIONS                                     #
###############################################################################

init_volumes() {
    log "Initializing MEGA volumes..."
    mapfile -t volumes < <(mega-mount 2>/dev/null | awk '/INSHARE on /{print $3}')
    [ ${#volumes[@]} -eq 0 ] && error_exit "No MEGA volumes available"
    log "Available volumes: ${volumes[*]}"
}

process_source() {
    local src="$1"
    log "Processing source: $src"
    
    if [ -f "$src" ]; then
        transfer_file "$src"
    elif [ -d "$src" ]; then
        process_directory "$src"
    else
        log "Skipping invalid path: $src"
        return 1
    fi
}

process_directory() {
    local dir="$1"
    log "Scanning directory: $dir"
    
    # Build find command for uncompressed files
    local find_uncompressed="find \"$dir\" -type f"
    for ext in "${COMPRESSED_FORMATS[@]}"; do
        find_uncompressed+=" ! -name \"*.$ext\""
    done
    
    # Process uncompressed files
    eval "$find_uncompressed -print0" | while IFS= read -r -d $'\0' file; do
        transfer_file "$file" "compress"
    done

    # Process compressed files
    local find_compressed="find \"$dir\" -type f \( "
    for ext in "${COMPRESSED_FORMATS[@]}"; do
        find_compressed+="-name \"*.$ext\" -o "
    done
    find_compressed="${find_compressed% -o } \) -print0"
    
    eval "$find_compressed" | while IFS= read -r -d $'\0' file; do
        transfer_file "$file" "no-compress"
    done
}

transfer_file() {
    local file="$1"
    local mode="${2:-auto}"
    local base_name=$(basename "$file")
    
    # Auto-detect compression for 'auto' mode
    if [ "$mode" = "auto" ]; then
        for ext in "${COMPRESSED_FORMATS[@]}"; do
            [[ "$file" = *.$ext ]] && mode="no-compress" && break
        done
    fi

    case "$mode" in
        "compress")
            compress_and_transfer "$file" "${base_name}.backup.tar.gz"
            ;;
        "no-compress")
            direct_transfer "$file" "${base_name}.backup"
            ;;
        *)
            log "Invalid transfer mode: $mode"
            return 1
            ;;
    esac
}

compress_and_transfer() {
    local src="$1" dest_name="$2"
    local tmp_file="${TMP_DIR}/${dest_name}"
    
    log "Compressing: $src → $dest_name"
    if ! run_command "tar -czf '$tmp_file' '$src'"; then
        log "Compression failed for: $src"
        safe_remove "$tmp_file"
        return 1
    fi
    
    transfer_to_volume "$tmp_file" "$dest_name"
    safe_remove "$tmp_file"
}

direct_transfer() {
    local src="$1" dest_name="$2"
    log "Transferring pre-compressed file: $(basename "$src")"
    transfer_to_volume "$src" "$dest_name"
}

transfer_to_volume() {
    local src="$1" dest_name="$2"
    local retries=3
    
    while (( retries-- > 0 )); do
        local vol="${volumes[$curr_vol_index]}"
        local free_space=$(get_free_space "$vol")
        local file_size=$(stat -c%s "$src")
        
        if (( file_size > free_space )); then
            if (( file_size > CHUNK_SIZE )); then
                split_and_transfer "$src" "$dest_name" "$file_size" && return 0
            else
                rotate_volume || return 1
                continue
            fi
        else
            run_command "mega-put '$src' '$vol/$dest_name'" && return 0
        fi
        sleep 5 # Wait before retry
    done
    
    log "Transfer failed after 3 attempts: $dest_name"
    return 1
}

get_free_space() {
    local volume="$1"
    local total_space=53687091200  # 50GB in bytes (default MEGA free account)
    local used_space=0
    
    # Get used space from mega-df output
    used_space=$(mega-df 2>/dev/null | grep -A 5 "$volume" | awk '/Used:/ {print $2}')
    
    # Calculate free space
    echo $((total_space - used_space))
}

split_and_transfer() {
    local src="$1"
    local dest_name="$2"
    local total_size="$3"
    local chunk_size=$CHUNK_SIZE
    local transferred=0
    local part_num=1
    
    while (( transferred < total_size )); do
        # Calculate remaining space on current volume
        local vol="${volumes[$curr_vol_index]}"
        local free_space=$(get_free_space "$vol")
        
        # Determine chunk size (smaller of remaining file or free space)
        local current_chunk=$(( free_space < chunk_size ? free_space : chunk_size ))
        current_chunk=$(( current_chunk > (total_size - transferred) ? (total_size - transferred) : current_chunk ))
        
        # Create temporary chunk file
        local chunk_file="${TMP_DIR}/${dest_name}.part${part_num}"
        run_command "dd if='$src' of='$chunk_file' bs=1 count=$current_chunk skip=$transferred 2>/dev/null" || {
            safe_remove "$chunk_file"
            return 1
        }
        
        # Transfer chunk
        run_command "mega-put '$chunk_file' '$vol/${dest_name}.part${part_num}'" || {
            safe_remove "$chunk_file"
            return 1
        }
        
        safe_remove "$chunk_file"
        (( transferred += current_chunk ))
        (( part_num++ ))
        
        # Rotate volume if current is full
        (( $(get_free_space "$vol") < MIN_FREE_SPACE )) && rotate_volume || return 1
    done
}

###############################################################################
#                          UTILITY FUNCTIONS                                  #
###############################################################################

# Logging system
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    [ "$DEBUG" -eq 1 ] && echo "$msg" >&2
    [ -n "$LOG_FILE" ] && echo "$msg" >> "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    [ -n "$NOTIFY_SCRIPT" ] && "$NOTIFY_SCRIPT" "Backup Failed: $1"
    exit 1
}

# Space management
rotate_volume() {
    ((curr_vol_index++))
    if (( curr_vol_index >= ${#volumes[@]} )); then
        log "All volumes exhausted"
        return 1
    fi
    log "Switching to volume: ${volumes[$curr_vol_index]}"
    return 0
}

# Cleanup
safe_remove() {
    [ "$PRODUCTION" -eq 1 ] && rm -f "$1" || log "DRY-RUN: Would remove $1"
}

run_command() {
    local cmd="$1"
    local full_cmd="[DRY-RUN] Would execute: $cmd"
    
    if [ "$PRODUCTION" -eq 1 ]; then
        full_cmd="EXECUTING: $cmd"
        eval "$cmd"
        local status=$?
    else
        local status=0
    fi
    
    [ "$DEBUG" -eq 1 ] && log "$full_cmd"
    return $status
}

###############################################################################
#                          EXECUTION FLOW                                     #
###############################################################################

main() {
    [ "$(id -u)" -ne 0 ] && error_exit "This script requires root privileges"
    
    mkdir -p "$TMP_DIR"
    init_volumes
    
    for src in "${SOURCES[@]}"; do
        process_source "$src" || continue
    done
    
    log "Backup completed successfully"
    [ -n "$NOTIFY_SCRIPT" ] && "$NOTIFY_SCRIPT" "Backup Completed"
}

main "$@"