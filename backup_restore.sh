#!/bin/bash
# restore_backup.sh - Ripristina la struttura originale dai backup singoli

RESTORE_DIR="./"
OUTPUT_DIR="./original_restored"

mkdir -p "$OUTPUT_DIR"

find "$RESTORE_DIR" -name 'backup_*.tar.gz' | while read -r backup_file; do
    # Estrai il percorso originale dal nome del file
    original_path=${backup_file#*backup_}
    original_path=${original_path%.tar.gz}
    original_path="$OUTPUT_DIR/${original_path}"  # Converte _ in /
    
    # Crea la directory di destinazione
    mkdir -p "$(dirname "$original_path")"
    
    # Estrai il file mantenendo i permessi
    tar -xzf "$backup_file" -C "$(dirname "$original_path")"
    
    echo "Ripristinato: $original_path"
done

echo "Ripristino completato in $OUTPUT_DIR"