#!/bin/bash

CONTAINER_NAME="fileserver-apache-ip"
PORT="8080"
DATA_DIR="/opt/public-files"

# ==========================================
# WICHTIG: SICHERHEITSEINSTELLUNG
# Tragen Sie hier die IP-Adresse Ihres 
# Haupt-Servers (Main API) ein!
# ==========================================
MAIN_SERVER_IP="123.456.78.90"

# Farben für das Terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$MAIN_SERVER_IP" == "123.456.78.90" ]; then
    echo -e "${RED}FEHLER: Bitte ändern Sie die MAIN_SERVER_IP im Skript auf die echte IP Ihres Haupt-Servers!${NC}"
    exit 1
fi

# Prüfen, ob der Container bereits existiert
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    echo -e "${YELLOW}Der Container '${CONTAINER_NAME}' existiert bereits.${NC}"
    echo "Was möchtest du tun?"
    echo "1) Installation abbrechen"
    echo "2) Container löschen und erneut installieren"
    echo "3) Komplett entfernen (Container & Firewall-Regel löschen)"
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
            echo "Entferne UFW Firewall Regel..."
            ufw delete allow from $MAIN_SERVER_IP to any port $PORT proto tcp > /dev/null 2>&1
            ufw delete allow $PORT/tcp > /dev/null 2>&1
            
            read -p "Soll der Ordner $DATA_DIR mit allen Dateien gelöscht werden? (y/n): " del_dir < /dev/tty
            if [[ "$del_dir" =~ ^[Yy]$ ]]; then
                echo "Lösche Verzeichnis $DATA_DIR..."
                rm -rf $DATA_DIR
            else
                echo "Verzeichnis $DATA_DIR und Dateien bleiben erhalten."
            fi
            echo -e "${GREEN}Deinstallation abgeschlossen.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Ungültige Eingabe. Abbruch.${NC}"
            exit 1
            ;;
    esac
fi

echo -e "${GREEN}Starte Installation...${NC}"

echo "[1/3] Erstelle Verzeichnis..."
mkdir -p $DATA_DIR

echo "[2/3] Konfiguriere UFW Firewall (Maximaler Schutz)..."
# Blockiert alle, ERLAUBT NUR DEN HAUPTSERVER auf Port 8080
ufw allow from $MAIN_SERVER_IP to any port $PORT proto tcp
# Falls die alte unsichere Regel noch existiert, wird sie gelöscht
ufw delete allow $PORT/tcp > /dev/null 2>&1

echo "[3/3] Starte sicheren PHP-Apache-Dateiserver..."
docker run -d \
  --name $CONTAINER_NAME \
  --restart unless-stopped \
  -p $PORT:80 \
  -v $DATA_DIR:/var/www/html:ro \
  php:8.2-apache

echo "------------------------------------------------"
echo -e "${GREEN}Fertig! Der DNS-Worker läuft auf Port $PORT.${NC}"
echo -e "${YELLOW}ACHTUNG: Nur die IP ${MAIN_SERVER_IP} darf darauf zugreifen!${NC}"
echo "Lege deine sichere dns_worker.php in $DATA_DIR ab."
