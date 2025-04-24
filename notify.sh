#!/bin/bash
# notify.sh - Invia notifiche formattate a Telegram

TELEGRAM_BOT_TOKEN="7941722837:AAFL4V0rv5mEGIQEZ7Dz74VkwKXKMSa49VQ"
TELEGRAM_CHAT_ID="243984267"

[ -z "$1" ] && echo "Usage: $0 \"notification message\"" && exit 1

# Determina icona in base al messaggio
if [[ "$1" == *"SUCCESS"* ]] || [[ "$1" == *"Completato"* ]]; then
  ICON="✅"
elif [[ "$1" == *"ERROR"* ]] || [[ "$1" == *"Fallito"* ]]; then
  ICON="❌"
else
  ICON="ℹ️"
fi

# Costruisci il messaggio con newline reali
MESSAGE=$(cat <<EOF
${ICON} MEGA Backup
—————————————
${1}
EOF
)

# Invia a Telegram
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  -d text="${MESSAGE}" \
  -d parse_mode="Markdown"

echo "Notifica inviata: ${1}"
exit 0