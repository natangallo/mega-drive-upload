#!/bin/bash

# Esegue il comando mega-mount e filtra le linee di interesse
volumes_list=$(mega-mount | grep -E 'ROOT on |INSHARE on ' | awk '{print $3}')

# Inizializza l'array
echo "# Array dei volumi destinazione"
echo "volumes=("

# Aggiunge ogni volume all'array
while IFS= read -r volume; do
  echo "  \"$volume\""
done <<< "$volumes_list"

# Chiude l'array
echo "  # Aggiungi altri volumi se necessario"
echo ")"
