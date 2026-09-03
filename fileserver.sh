#!/bin/bash

CONTAINER_NAME="secure-php-server"
PORT="8080"
DATA_DIR="/opt/public-files"
CONFIG_FILE="/opt/secure-server-firewall.conf"

# Farben für das Terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Funktion zum sauberen Löschen der Firewall-Regeln (UFW & Docker-Iptables)
cleanup_firewall() {
    # 1. UFW bereinigen
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        if [ -n "$ALLOWED_IP" ]; then
            ufw delete allow from $ALLOWED_IP to any port $PORT proto tcp > /dev/null 2>&1
            # Docker iptables ACCEPT Regel löschen
            iptables -D DOCKER-USER -p tcp --dport $PORT -s $ALLOWED_IP -j ACCEPT > /dev/null 2>&1
        fi
    fi
    ufw delete allow $PORT/tcp > /dev/null 2>&1
    
    # Docker iptables DROP Regel löschen
    iptables -D DOCKER-USER -p tcp --dport $PORT -j DROP > /dev/null 2>&1
}

# Funktion zum Aufspüren und Zerstören von Geister-Containern
cleanup_ghost_containers() {
    BLOCKING_CID=$(docker ps -a -q --filter "publish=${PORT}")
    if [ -n "$BLOCKING_CID" ]; then
        for cid in $BLOCKING_CID; do
            NAME=$(docker inspect --format '{{.Name}}' $cid | sed 's/\///')
            if [ "$NAME" != "$CONTAINER_NAME" ]; then
                echo -e "${YELLOW}Entferne alten/blockierenden Container ('$NAME') auf Port $PORT...${NC}"
                docker rm -f $cid > /dev/null 2>&1
            fi
        done
    fi
}

# ---------------------------------------------------------
# 1. PRÜFEN OB UNSER CONTAINER BEREITS EXISTIERT
# ---------------------------------------------------------
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    echo -e "${YELLOW}Der Container '${CONTAINER_NAME}' existiert bereits.${NC}"
    echo "Was möchtest du tun?"
    echo "1) Installation abbrechen"
    echo "2) Container neu installieren/konfigurieren (Dateien bleiben erhalten)"
    echo "3) Komplett entfernen (Container, Geister-Container, Config, Firewall & Dateien löschen)"
    read -p "Wähle eine Option (1/2/3): " choice < /dev/tty

    case $choice in
        1)
            echo "Abbruch."
            exit 0
            ;;
        2)
            echo "Lösche alten Container..."
            docker rm -f $CONTAINER_NAME > /dev/null 2>&1
            cleanup_ghost_containers
            cleanup_firewall
            ;;
        3)
            echo "Entferne Haupt-Container..."
            docker rm -f $CONTAINER_NAME > /dev/null 2>&1
            cleanup_ghost_containers
            
            echo "Bereinige Firewall-Regeln (UFW & Docker)..."
            cleanup_firewall
            
            read -p "Soll der Ordner $DATA_DIR mit ALLEN Dateien wirklich gelöscht werden? (y/n): " del_dir < /dev/tty
            if [[ "$del_dir" =~ ^[Yy]$ ]]; then
                echo "Lösche Verzeichnis $DATA_DIR..."
                rm -rf $DATA_DIR
            else
                echo "Verzeichnis $DATA_DIR bleibt erhalten."
            fi
            
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
cleanup_ghost_containers

# ---------------------------------------------------------
# 2. FIREWALL PARAMETER ABFRAGEN
# ---------------------------------------------------------
ASK_CONFIG=true

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
        cleanup_firewall
    fi
fi

if [ "$ASK_CONFIG" = true ]; then
    echo -e "\n${CYAN}Wie soll die Firewall konfiguriert werden?${NC}"
    echo "1) Offen für alle (Nicht empfohlen für interne APIs)"
    echo "2) Beschränkt auf eine bestimmte IP (Maximaler Schutz zwingt auch Docker zur Blockade!)"
    read -p "Wähle eine Option (1/2): " fw_choice < /dev/tty
    
    if [ "$fw_choice" == "1" ]; then
        FIREWALL_MODE="open"
        ALLOWED_IP=""
    elif [ "$fw_choice" == "2" ]; then
        FIREWALL_MODE="restricted"
        read -p "Bitte gib die erlaubte IP-Adresse ein: " ALLOWED_IP < /dev/tty
    else
        echo -e "${RED}Ungültige Eingabe. Abbruch.${NC}"
        exit 1
    fi
    
    echo "FIREWALL_MODE=\"$FIREWALL_MODE\"" > "$CONFIG_FILE"
    echo "ALLOWED_IP=\"$ALLOWED_IP\"" >> "$CONFIG_FILE"
fi

# ---------------------------------------------------------
# 3. VERZEICHNISSE & FIREWALL & CONTAINER STARTEN
# ---------------------------------------------------------
echo -e "\n[1/3] Erstelle Verzeichnis ($DATA_DIR)..."
mkdir -p $DATA_DIR

echo "[2/3] Wende strenge Firewall-Regeln an..."
if [ "$FIREWALL_MODE" == "open" ]; then
    ufw allow $PORT/tcp > /dev/null
    echo -e "-> ${YELLOW}Port $PORT wurde für das gesamte Internet geöffnet.${NC}"
else
    # 1. UFW für den Host setzen
    ufw allow from $ALLOWED_IP to any port $PORT proto tcp > /dev/null
    # 2. Docker zwingen, alle fremden IPs zu droppen (Der ultimative Fix!)
    iptables -I DOCKER-USER 1 -p tcp --dport $PORT -j DROP
    iptables -I DOCKER-USER 1 -p tcp --dport $PORT -s $ALLOWED_IP -j ACCEPT
    
    echo -e "-> ${GREEN}Port $PORT wurde exklusiv für die IP $ALLOWED_IP auf tiefster Ebene geöffnet.${NC}"
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
    echo -e "Sicherheitsstatus: ${GREEN}Maximaler Schutz aktiv (Nur IP $ALLOWED_IP kommt durch Docker)${NC}"
else
    echo -e "Sicherheitsstatus: ${RED}Kein IP-Schutz (Offen für alle)${NC}"
fi
echo "Lege deine PHP-Skripte oder Web-Dateien in $DATA_DIR ab."
