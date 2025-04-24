# MEGA Backup System (Proxmox Optimized)

![MEGA Logo](https://mega.nz/favicon.ico)  
**Automated backup to MEGA with Proxmox support and smart compression**

---

## 📌 Overview

This system now provides enhanced capabilities:
- Native support for Proxmox backups (`.vma.gz`, `.tar.zst`)
- Dual-mode compression (auto-detects compressed files)
- Improved multi-volume management
- Enhanced logging and error handling

---

## 📂 File Structure (Updated)

```
mega-backup/
├── perform_backup.sh          # Main script (v4.0)
├── check_session.sh           # MEGA session verification  
├── notify.sh                  # Notification handler
├── mega-backup.log            # Auto-generated log file
└── README.md                  # This documentation
```

---

## 🛠 Configuration (v4.0 Updates)

### 🔧 Main Script (`perform_backup.sh`)

| Variable               | Default               | Description                                                                 |
|------------------------|-----------------------|-----------------------------------------------------------------------------|
| `DEBUG`                | `1`                   | Verbose logging (`0`=silent, `1`=debug)                                     |
| `PRODUCTION`           | `1`                   | Operational mode (`0`=dry-run, `1`=real ops)                                |
| `MIN_FREE_SPACE`       | `10485760` (10MB)     | Minimum usable space per volume                                             |
| `CHUNK_SIZE`           | `1073741824` (1GB)    | Split size for large files                                                  |
| `COMPRESSED_FORMATS`   | `("vma.gz" "tar.zst" "tar.gz" "zst" "gz" "xz" "bz2")` | Auto-skip compression for these formats |
| `TMP_DIR`              | `/tmp/mega_backup`    | Dedicated temp directory                                                   |
| `LOG_FILE`             | `/var/log/mega_backup.log` | Central log file                                                        |

### 🔄 New Workflow

1. **Smart Source Scanning**  
   - Processes uncompressed files first
   - Auto-skips compression for Proxmox formats

2. **Space-Aware Transfer**  
   ```mermaid
   graph TD
     A[Check Volume Space] --> B{File > Space?}
     B -->|Yes| C[Split File]
     B -->|No| D[Direct Transfer]
     C --> E[Rotate Volume if Full]
   ```

3. **Enhanced Recovery**  
   ```bash
   # Reassemble split Proxmox backups:
   cat vzdump.part* > complete.vma.gz
   qm restore <VMID> complete.vma.gz
   ```

---

## 🚀 Usage Examples

```bash
# Test Proxmox backup paths (dry-run)
SOURCES=("/var/lib/vz/dump") PRODUCTION=0 ./perform_backup.sh

# Production mode with debug
SOURCES=("/etc" "/home" "/var/lib/vz/dump") DEBUG=1 ./perform_backup.sh
```

---

## 🆕 v4.0 Features

1. **Proxmox-Optimized**  
   - Native handling of `.vma.gz` and `.tar.zst`
   - Preserves original backup names

2. **Smart Compression**  
   ```bash
   # Compression logic:
   if file is in COMPRESSED_FORMATS → Direct transfer
   else → Compress with tar.gz
   ```

3. **Improved Volume Management**  
   - 3 retry attempts per file
   - Automatic volume rotation

---

## 📝 Best Practices (Updated)

1. **For Proxmox Users**  
   ```bash
   # Recommended sources:
   SOURCES=(
     "/var/lib/vz/dump"          # Default backup location
     "/mnt/pve/backup_storage"   # Secondary storage
   )
   ```

2. **Security**  
   ```bash
   # Set proper permissions:
   chmod 700 perform_backup.sh
   chown root:root perform_backup.sh
   ```

3. **Monitoring**  
   ```bash
   # Watch live progress:
   tail -f /var/log/mega_backup.log | grep -E 'Transferring|Compressing'
   ```

---

## 🛑 Error Recovery (Enhanced)

**Scenario**: Failed transfer of split backup  
**Solution**:
```bash
# 1. List all parts
mega-find //backups --pattern="*.part*"

# 2. Download missing chunks
mega-get //backups/vzdump.part3.tar.gz .

# 3. Manual reassembly
cat vzdump.part*.tar.gz > restored.vma.gz
```

---

## 📜 License  
MIT License - Free for personal and commercial use

---

> ✍️ **Last Updated**: 2024-04-20  
> 🏷 **Version**: 4.0  
> 👨💻 **Maintainer**: Natan Gallo  
> 🔗 **Compatibility**: Proxmox VE 7+, MEGA-CMD 1.5.0+
```

Key changes made:
1. Added Proxmox-specific documentation
2. Updated configuration variables to match v4.0
3. Added visual workflow diagram
4. Included Proxmox recovery examples
5. Highlighted new v4.0 features section
6. Updated best practices for Proxmox environments
7. Added compatibility notice
8. Improved structure with clear sections
