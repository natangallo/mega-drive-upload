#!/bin/bash
# notify.sh - Invia una notifica via Telegram e Email
#
# Configurazioni (modifica questi valori secondo le tue impostazioni)
TELEGRAM_BOT_TOKEN="52945090850:25LKJFD98R0LA9E0843POJFDA09834J"  # Inserisci il token del tuo bot Telegram
TELEGRAM_CHAT_ID="602704974"                                        # Inserisci l'ID chat dove inviare il messaggio
EMAIL_DESTINATARIO="EMAIL@DOMAIN.com"                                 # Inserisci l'indirizzo email di destinazione

# Verifica che sia stato passato un messaggio come parametro
if [ -z "$1" ]; then
  echo "Utilizzo: $0 \"Messaggio di notifica\""
  exit 1
fi

MESSAGE="$1"

# Funzione: invia notifica via Telegram
send_telegram() {
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d text="$MESSAGE"
}

# Funzione: invia notifica via Email
send_email() {
  echo "$MESSAGE" | mail -s "Notifica MEGA Backup" "$EMAIL_DESTINATARIO"
}

# Invia entrambe le notifiche
send_telegram
# send_email

echo "Notifica inviata: $MESSAGE"
exit 0
