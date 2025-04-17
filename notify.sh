#!/bin/bash
# notify.sh - Invia notifiche formattate a Telegram

TTELEGRAM_BOT_TOKEN="your-bot:239487239847LONG-TOKEN098530249l"  # Inserisci il token del tuo bot Telegram
TELEGRAM_CHAT_ID="00CHAT-ID000"                                        # Inserisci l'ID chat dove inviare il messaggio
EMAIL_DESTINATARIO="EMAIL@DOMAIN.com"

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