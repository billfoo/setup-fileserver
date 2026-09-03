#!/bin/bash

CONTAINER_NAME="secure-php-server"
PORT="8080"
DATA_DIR="/opt/public-files"

# Farben für das Terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Funktion zum sauberen Löschen aller Firewall-Regeln für diesen Port
cleanup_ufw() {
    # Sucht alle UFW-Regelnummern für den Port und löscht sie absteigend (um Verschiebungen zu vermeiden)
    for rule in $(ufw status numbered | grep -E "\b${PORT}(/tcp)?\b" | awk -F"[][]" '{print $2}' | tr -d ' ' | sort -rn); do
        yes | ufw delete $rule > /dev/null 2>&1
    done
}

# ---------------------------------------------------------
# 1. PRÜFEN OB CONTAINER BEREITS EXISTIERT
# ---------------------------------------------------------
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    echo -e "${YELLOW}Der Container '${CONTAINER_NAME}' existiert bereits.${NC}"
    echo "Was möchtest du tun?"
    echo "1) Installation abbrechen"
    echo "2) Container löschen und neu installieren/konfigurieren"
    echo "3) Komplett entfernen (Container & Firewall-Regeln löschen)"
    read -p "Wähle eine Option (1/2/3): " choice < /dev/tty

    case $choice in
        1)
            echo "Abbruch."
            exit 0
            ;;
        2)
            echo "Lösche alten Container..."
            docker rm -f $CONTAINER_NAME > /dev/null
            ;;
        3)
            echo "Entferne Container..."
            docker rm -f $CONTAINER_NAME > /dev/null
            echo "Bereinige Firewall-Regeln..."
            cleanup_ufw
            
            read -p "Soll der Ordner $DATA_DIR mit allen Dateien gelöscht werden? (y/n): " del_dir < /dev/tty
            if [[ "$del_dir" =~ ^[Yy]$ ]]; then
                echo "Lösche Verzeichnis $DATA_DIR..."
                rm -rf $DATA_DIR
            else
                echo "Verzeichnis $DATA_DIR bleibt erhalten."
            fi
            
            echo -e "${GREEN}Deinstallation komplett abgeschlossen.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Ungültige Eingabe. Abbruch.${NC}"
            exit 1
            ;;
    esac
fi

echo -e "\n${GREEN}=== Starte Installation / Konfiguration ===${NC}"

# ---------------------------------------------------------
# 2. FIREWALL STATUS DIREKT AUS UFW AUSLESEN
# ---------------------------------------------------------
FIREWALL_MODE="unknown"
DETECTED_IP=""
ASK_CONFIG=true

# Aktuelle Regel für den Port aus der Firewall holen
CURRENT_RULE=$(ufw status | awk -v port="$PORT" '$1 == port || $1 == port"/tcp" {print $0}' | head -n 1)

if [[ -n "$CURRENT_RULE" ]]; then
    if [[ "$CURRENT_RULE" == *"Anywhere"* ]]; then
        FIREWALL_MODE="open"
    else
        FIREWALL_MODE="restricted"
        # Die IP ist das letzte Wort in der UFW Ausgabe
        DETECTED_IP=$(echo "$CURRENT_RULE" | awk '{print $NF}')
    fi

    echo -e "\n${CYAN}Bestehende Firewall-Konfiguration erkannt:${NC}"
    if [ "$FIREWALL_MODE" == "open" ]; then
        echo -e "-> Der Port $PORT ist aktuell ${RED}OFFEN FÜR ALLE${NC}."
    else
        echo -e "-> Der Port $PORT ist aktuell ${GREEN}BESCHRÄNKT auf die IP: $DETECTED_IP${NC}."
    fi
    
    read -p "Möchtest du diese Parameter beibehalten? (y = Behalten / n = Ändern): " keep_config < /dev/tty
    if [[ "$keep_config" =~ ^[Yy]$ ]]; then
        ASK_CONFIG=false
        ALLOWED_IP="$DETECTED_IP"
    else
        echo "Lösche alte Firewall-Regeln vor der Neukonfiguration..."
        cleanup_ufw
    fi
fi

# ---------------------------------------------------------
# 3. FIREWALL PARAMETER ABFRAGEN (FALLS GEWÜNSCHT/NEU)
# ---------------------------------------------------------
if [ "$ASK_CONFIG" = true ]; then
    echo -e "\n${CYAN}Wie soll die Firewall für den Server konfiguriert werden?${NC}"
    echo "1) Offen für alle (Nicht empfohlen für interne Skripte/APIs)"
    echo "2) Beschränkt auf eine bestimmte IP (Maximaler Schutz - Nur diese IP darf zugreifen)"
    read -p "Wähle eine Option (1/2): " fw_choice < /dev/tty
    
    if [ "$fw_choice" == "1" ]; then
        FIREWALL_MODE="open"
        ALLOWED_IP=""
    elif [ "$fw_choice" == "2" ]; then
        FIREWALL_MODE="restricted"
        read -p "Bitte gib die erlaubte IP-Adresse ein: " ALLOWED_IP < /dev/tty
        
        # Kurze Plausibilitätsprüfung
        if [[ ! $ALLOWED_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${YELLOW}Warnung: Das Format der IP ($ALLOWED_IP) sieht ungewöhnlich aus, wird aber übernommen.${NC}"
        fi
    else
        echo -e "${RED}Ungültige Eingabe. Abbruch.${NC}"
        exit 1
    fi
fi

# ---------------------------------------------------------
# 4. VERZEICHNISSE & UFW & CONTAINER STARTEN
# ---------------------------------------------------------
echo -e "\n[1/3] Erstelle Verzeichnis ($DATA_DIR)..."
mkdir -p $DATA_DIR

echo "[2/3] Wende UFW Firewall-Regeln an..."
if [ "$FIREWALL_MODE" == "open" ]; then
    ufw allow $PORT/tcp > /dev/null
    echo -e "-> ${YELLOW}Port $PORT wurde für das gesamte Internet geöffnet.${NC}"
else
    ufw allow from $ALLOWED_IP to any port $PORT proto tcp > /dev/null
    echo -e "-> ${GREEN}Port $PORT wurde exklusiv für die IP $ALLOWED_IP geöffnet.${NC}"
fi

echo "[3/3] Starte sicheren PHP-Apache-Server (Docker)..."
docker run -d \
  --name $CONTAINER_NAME \
  --restart unless-stopped \
  -p $PORT:80 \
  -v $DATA_DIR:/var/www/html:ro \
  php:8.2-apache > /dev/null

echo "------------------------------------------------"
echo -e "${GREEN}Fertig! Der Webserver läuft auf Port $PORT.${NC}"
if [ "$FIREWALL_MODE" == "restricted" ]; then
    echo -e "Sicherheitsstatus: ${GREEN}Maximaler Schutz aktiv (Nur IP $ALLOWED_IP hat Zugriff)${NC}"
else
    echo -e "Sicherheitsstatus: ${RED}Kein IP-Schutz (Offen für alle)${NC}"
fi
echo "Lege deine PHP-Skripte oder Web-Dateien in $DATA_DIR ab."
