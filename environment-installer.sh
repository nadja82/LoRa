#!/usr/bin/env bash
# install_meshtastic.sh
# Automatische Installation von dialog und meshtastic CLI auf Linux

set -e  # Script bricht bei Fehler ab

echo "==== Nadja's Auto-Installer für Meshtastic & Dialog ===="

# Root-Check
if [[ $EUID -ne 0 ]]; then
   echo "Bitte mit sudo oder als root starten."
   exit 1
fi

# Paketmanager erkennen
if command -v apt >/dev/null 2>&1; then
    PKG_MANAGER="apt"
elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"
else
    echo "Kein unterstützter Paketmanager gefunden (apt oder pacman)."
    exit 1
fi

# Installation je nach System
if [[ $PKG_MANAGER == "apt" ]]; then
    echo "[*] Aktualisiere Paketliste..."
    apt update -y
    echo "[*] Installiere Dialog & Python3 Pip..."
    apt install -y dialog python3 python3-pip
elif [[ $PKG_MANAGER == "pacman" ]]; then
    echo "[*] Aktualisiere Paketliste..."
    pacman -Sy --noconfirm
    echo "[*] Installiere Dialog & Python3 Pip..."
    pacman -S --noconfirm dialog python python-pip
fi

# Meshtastic via pip installieren
echo "[*] Installiere Meshtastic CLI..."
pip3 install --upgrade meshtastic

# Test
if command -v meshtastic >/dev/null 2>&1; then
    echo "✅ Meshtastic erfolgreich installiert!"
    meshtastic --version
else
    echo "❌ Fehler: Meshtastic wurde nicht gefunden."
    exit 1
fi

# Install requirements for add-apt-repository
sudo apt install software-properties-common
# Add Meshtastic repo
sudo add-apt-repository ppa:meshtastic/beta
# Install meshtasticd
sudo apt install meshtasticd

echo "==== Installation abgeschlossen ===="
echo "Starte mit: meshtastic --help"
