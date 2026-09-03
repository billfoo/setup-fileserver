#!/bin/bash

CONTAINER_NAME="dns-worker-node"
PORT="8080"
DATA_DIR="/opt/public-files"
CONFIG_FILE="/opt/dns-worker-firewall.conf"

# Farben für das Terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Funktion zum Bereinigen der alten Firewall-Regeln
cleanup_ufw() {
    # Lösche pauschale Öffnung (falls vorhanden)
    ufw delete allow $PORT/tcp > /dev/null 2>&1
    
    # Lösche spezifische IP-Öffnung (falls in Config gespeichert)
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        if [ "$FIREWALL_MODE" == "restricted" ] && [ -n "$ALLOWED_IP" ]; then
            ufw delete allow from $ALLOWED_IP to any port $PORT proto tcp > /dev/null 2>&1
        fi
    fi
}

# ---------------------------------------------------------
# 1. PRÜFEN OB CONTAINER BEREITS EXISTIERT
# ---------------------------------------------------------
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    echo -e "${YELLOW}Der Container '${CONTAINER_NAME}' existiert bereits.${NC}"
    echo "Was möchtest du tun?"
    echo "1) Installation abbrechen"
    echo "2) Container löschen und neu installieren/konfigurieren"
    echo "3) Komplett entfernen (Container, Config & Firewall-Regeln löschen)"
    read -p "Wähle eine Option (1/2/3): " choice < /dev/tty

    case $choice in
        1)
            echo "Abbruch."
            exit 0
            ;;
        2)
            echo "Lösche alten Container..."
            docker rm -f $CONTAINER_NAME
            ;;
        3)
            echo "Entferne Container..."
            docker rm -f $CONTAINER_NAME
            echo "Bereinige Firewall-Regeln..."
            cleanup_ufw
            
            read -p "Soll der Ordner $DATA_DIR mit allen Dateien gelöscht werden? (y/n): " del_dir < /dev/tty
            if [[ "$del_dir" =~ ^[Yy]$ ]]; then
                echo "Lösche Verzeichnis $DATA_DIR..."
                rm -rf $DATA_DIR
            else
                echo "Verzeichnis $DATA_DIR bleibt erhalten."
            fi
            
            echo "Lösche Konfigurationsdatei..."
            rm -f $CONFIG_FILE
            
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
# 2. FIREWALL PARAMETER ABFRAGEN (INTERAKTIV)
# ---------------------------------------------------------
ASK_CONFIG=true

# Wenn bereits eine Config existiert, frage ob sie behalten werden soll
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo -e "\n${CYAN}Bestehende Firewall-Konfiguration gefunden:${NC}"
    if [ "$FIREWALL_MODE" == "open" ]; then
        echo -e "-> Der Port $PORT ist aktuell ${RED}OFFEN FÜR ALLE${NC}."
    else
        echo -e "-> Der Port $PORT ist aktuell ${GREEN}BESCHRÄNKT auf die IP: $ALLOWED_IP${NC}."
    fi
    
    read -p "Möchtest du diese Parameter beibehalten? (y = Behalten / n = Ändern): " keep_config < /dev/tty
    if [[ "$keep_config" =~ ^[Yy]$ ]]; then
        ASK_CONFIG=false
    else
        echo "Lösche alte Firewall-Regeln vor der Neukonfiguration..."
        cleanup_ufw
    fi
fi

# Wenn keine Config existiert ODER der Nutzer sie ändern will
if [ "$ASK_CONFIG" = true ]; then
    echo -e "\n${CYAN}Wie soll die Firewall für den DNS-Worker konfiguriert werden?${NC}"
    echo "1) Offen für alle (Nicht empfohlen, da jeder den Server aufrufen kann)"
    echo "2) Beschränkt auf MAIN_SERVER_IP (Maximaler Schutz - Nur Ihre Haupt-API darf zugreifen)"
    read -p "Wähle eine Option (1/2): " fw_choice < /dev/tty
    
    if [ "$fw_choice" == "1" ]; then
        FIREWALL_MODE="open"
        ALLOWED_IP=""
    elif [ "$fw_choice" == "2" ]; then
        FIREWALL_MODE="restricted"
        read -p "Bitte gib die MAIN_SERVER_IP (IP deiner Haupt-API) ein: " ALLOWED_IP < /dev/tty
        
        # Kurze Plausibilitätsprüfung für die IP
        if [[ ! $ALLOWED_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${YELLOW}Warnung: Das Format der IP ($ALLOWED_IP) sieht ungewöhnlich aus, wird aber übernommen.${NC}"
        fi
    else
        echo -e "${RED}Ungültige Eingabe. Abbruch.${NC}"
        exit 1
    fi
    
    # Speichere die neue Config
    echo "FIREWALL_MODE=\"$FIREWALL_MODE\"" > "$CONFIG_FILE"
    echo "ALLOWED_IP=\"$ALLOWED_IP\"" >> "$CONFIG_FILE"
fi

# ---------------------------------------------------------
# 3. VERZEICHNISSE & UFW & CONTAINER STARTEN
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

echo "[3/3] Starte sicheren PHP-Apache-Dateiserver (Docker)..."
docker run -d \
  --name $CONTAINER_NAME \
  --restart unless-stopped \
  -p $PORT:80 \
  -v $DATA_DIR:/var/www/html:ro \
  php:8.2-apache > /dev/null

echo "------------------------------------------------"
echo -e "${GREEN}Fertig! Der DNS-Worker läuft auf Port $PORT.${NC}"
if [ "$FIREWALL_MODE" == "restricted" ]; then
    echo -e "Sicherheitsstatus: ${GREEN}Maximaler Schutz aktiv (Nur IP $ALLOWED_IP)${NC}"
else
    echo -e "Sicherheitsstatus: ${RED}Kein IP-Schutz (Offen für alle)${NC}"
fi
echo "Lege deine sichere dns_worker.php in $DATA_DIR ab."
