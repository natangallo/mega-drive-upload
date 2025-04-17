# MEGA Backup System

![MEGA Logo](https://mega.nz/favicon.ico)  
**Automated compressed backup to MEGA cloud with multi-volume support**

---

## 📌 Overview

This system provides an automated way to:
- Compress files/folders
- Split large backups across multiple MEGA volumes
- Handle session management and error recovery
- Support both production and dry-run modes

---

## 📂 File Structure

```
mega-backup/
├── perform_backup.sh          # Main backup script
├── check_session.sh           # MEGA session verification
├── notify.sh                  # Notification handler
└── README.md                  # Documentation
```

---

## 🛠 Configuration

### 🔧 Main Script (`perform_backup.sh`)

| Variable               | Default      | Description                                                                 |
|------------------------|--------------|-----------------------------------------------------------------------------|
| `DEBUG`                | `1`          | Enable verbose logging (`0`=silent, `1`=debug)                              |
| `PRODUCTION`           | `1`          | Operational mode (`0`=dry-run, `1`=real operations)                        |
| `block_min_size`       | `10485760`   | Minimum free space (10MB) to consider a volume usable                       |
| `split_chunk_size`     | `1073741824` | Split size for large files (1GB)                                            |
| `TMP_DIR`              | `/tmp`       | Temporary directory for compressed files                                    |
| `sources`              | -            | Array of paths to back up                                                   |

### 🔐 Session Check (`check_session.sh`)

Verifies MEGA login status with exit codes:
- `0`: Session active
- `1`: Session expired
- `2`: Check failed
- `3`: Unknown state

### ✉️ Notifications (`notify.sh`)

Sends formatted alerts to Telegram with:
- ✅ Success messages
- ❌ Error alerts
- ℹ️ Information notices

---

## 🔄 Workflow

1. **Session Verification**  
   - Validates active MEGA session
2. **Volume Discovery**  
   - Detects available MEGA volumes
3. **Space Calculation**  
   - Checks free space on each volume
4. **Backup Execution**  
   - Compresses source files
   - Splits large files across volumes
   - Transfers to MEGA cloud

---

## 🚀 Usage

```bash
# Normal mode
./perform_backup.sh

# Dry-run test
PRODUCTION=0 ./perform_backup.sh

# Silent mode
DEBUG=0 ./perform_backup.sh
```

---

## 🛑 Error Recovery

To restore split backups:
```bash
# Download all parts
mega-get "//remote/path/backup.part*.tar.gz" .

# Reassemble
cat backup.part*.tar.gz > full_backup.tar.gz

# Verify
tar -tzf full_backup.tar.gz
```

---

## 📝 Best Practices

1. **Security**
   - Set scripts as executable only
   ```bash
   chmod 700 *.sh
   ```
   
2. **Monitoring**
   - Check logs regularly
   ```bash
   tail -f /var/log/mega-backup.log
   ```

3. **Maintenance**
   - Rotate backup sources periodically
   - Update credentials every 3-6 months

---

## 📜 License
MIT License - Free for personal and commercial use

---

> ✍️ **Last Updated**: $(date +%Y-%m-%d)  
> 🏷 **Version**: 2.1  
> 👨💻 **Maintainer**: Natan Gallo