#!/bin/bash
# check_session.sh - Verifica la sessione MEGA

# Modalita verbose (0=disabilitato, 1=abilitato)
VERBOSE=1

# Esegui mega-whoami per controllare la sessione
session_output=$(mega-whoami 2>&1)
exit_code=$?

if [ $exit_code -ne 0 ]; then
    # Caso 1: Comando fallito completamente
    echo "ERRORE: Impossibile verificare la sessione"
    [ -n "$NOTIFY_SCRIPT" ] && notify.sh "Errore verifica sessione MEGA: $session_output"
    exit 2
elif [[ "$session_output" == *"Not logged in"* ]] || [[ "$session_output" == *"ERR"* ]]; then
    # Caso 2: Non autenticato
    [ "$VERBOSE" = "1" ] && echo "Sessione scaduta o non autenticata"
    [ -n "$NOTIFY_SCRIPT" ] && notify.sh "Sessione MEGA scaduta. Riattivare l'autenticazione."
    exit 1
elif [[ "$session_output" == *"Account e-mail:"* ]]; then
    # Caso 3: Autenticato correttamente
    [ "$VERBOSE" = "1" ] && echo "Sessione attiva: $(echo "$session_output" | grep "Account e-mail:")"
    exit 0
else
    # Caso 4: Output non riconosciuto
    echo "ERRORE: Output non riconosciuto da mega-whoami"
    [ -n "$NOTIFY_SCRIPT" ] && notify.sh "Errore sconosciuto verifica sessione MEGA"
    exit 3
fi
