#!/bin/bash

CONTAINER_NAME="public-fileserver"
PORT="8080"
DATA_DIR="/opt/public-files"

# Farben für das Terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Prüfen, ob der Container bereits existiert
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    echo -e "${YELLOW}Der Container '${CONTAINER_NAME}' existiert bereits.${NC}"
    echo "Was möchtest du tun?"
    echo "1) Installation abbrechen"
    echo "2) Container löschen und erneut installieren"
    echo "3) Komplett entfernen (Container löschen & Firewall Port $PORT schließen)"
    # Wichtig: < /dev/tty ermöglicht interaktive Eingaben bei curl-Ausführung
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
            
            echo "Schließe Firewall Port $PORT..."
            ufw delete allow $PORT/tcp
            
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
# Legt die Testdatei nur an, wenn der Ordner komplett leer ist
if [ -z "$(ls -A $DATA_DIR 2>/dev/null)" ]; then
    echo "Das ist meine komplett unabhaengige Datei" > $DATA_DIR/test.txt
fi

echo "[2/3] Konfiguriere UFW Firewall (Port $PORT/tcp)..."
ufw allow $PORT/tcp

echo "[3/3] Starte unabhängigen Nginx-Dateiserver..."
docker run -d \
  --name $CONTAINER_NAME \
  --restart unless-stopped \
  -p $PORT:80 \
  -v $DATA_DIR:/usr/share/nginx/html:ro \
  nginx:alpine

echo "------------------------------------------------"
echo -e "${GREEN}Fertig! Der Dateiserver läuft auf Port $PORT.${NC}"
echo "Lege deine Dateien in $DATA_DIR ab."
