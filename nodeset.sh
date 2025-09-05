#!/usr/bin/env bash
# nadja-node-setup-once.sh — Meshtastic Node Setup (one-shot) via dialog + Progressbar
# Requires: dialog, meshtastic (Python CLI)
# Uses transactional updates: --begin-edit / --commit-edit   (docs: mbug wiki)
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "Fehlt: $1"; exit 1; }; }
need dialog; need meshtastic

log="/tmp/nadja-node-setup.log"

PORT=$(dialog --stdout --inputbox "USB-Port (z.B. /dev/ttyUSB0)" 8 60 "/dev/ttyUSB0") || exit
[ -n "$PORT" ] || exit 1
MT="meshtastic --port $PORT"

# ---------- REGION ----------
REG=$(dialog --stdout --no-tags --menu "Region / Frequenzband" 14 70 6 \
  EU_868 "Europa 868/869 MHz (Standard EU)" \
  EU_433 "Europa 433 MHz (Low power)" \
  US_915 "USA 915 MHz" \
  SKIP   "überspringen")
[ -z "${REG:-}" ] && exit 0

# ---------- ROLLE ----------
ROLE=$(dialog --stdout --no-tags --menu "Geräterolle" 14 72 7 \
  CLIENT       "Standard-Teilnehmer (rebroadcast möglich)" \
  CLIENT_MUTE  "Teilnahme ohne Rebroadcast (dichte Netze)" \
  ROUTER       "Router (stationär, weiterleiten, kein BLE)" \
  REPEATER     "Repeater (starkes Weiterleiten, minimal UI)" \
  TRACKER      "Tracker (spricht nur wenn nötig)" \
  SKIP         "überspringen")
[ -z "${ROLE:-}" ] && exit 0

# ---------- POWER PROFILE ----------
PWR=$(dialog --stdout --no-tags --menu "Power / Sleep Profile" 16 74 10 \
  BAL "Ausgewogen: Display 20s, PowerSaving AUS" \
  LSL "Light-Sleep OPTIMAL (kein DeepSleep): ls=120, wake=15, bt=60, disp=12" \
  ADV "Aggressives Sparen (kein Zeitplan): ls=300, wake=10, bt=60" \
  EXP "Experimentell: UltraSaver Light-Sleep: ls=60, wake=5, bt=30, disp=8" \
  SKIP "überspringen")
[ -z "${PWR:-}" ] && exit 0

# ---------- NETZ-OPTIONEN ----------
readarray -t NETOPTS < <(dialog --stdout --checklist "Netz / Kompatibilität" 14 76 10 \
  REB_ALL   "Rebroadcast = ALL (volle Weiterleitung)" on \
  NEIGH_ON  "Neighbor-Info aktivieren" on \
  NEIGH_LORA "Neighbor-Info auch via LoRa senden" off \
  NEIGH_6H  "Neighbor-Intervall 6h (21600s)" on \
  NEIGH_4H  "Neighbor-Intervall 4h (14400s)" off \
  SAND_F    "Store & Forward: aktivieren (Client)" off \
  SAND_F_SRV "Store & Forward: Server + Heartbeat" off)
[ -z "${NETOPTS:-}" ] && NETOPTS=()

# ---------- REICHWEITE ----------
RNG=$(dialog --stdout --no-tags --menu "Reichweite / Modem-Preset" 16 78 10 \
  STD          "LONG_FAST (Standard, beste Mesh-Kompatibilität)" \
  LONGSLOW     "LONG_SLOW (mehr Reichweite, höhere Airtime)" \
  VLONGSLOW    "VERY_LONG_SLOW (EXPERIMENTELL: max Reichweite)" \
  SKIP         "überspringen")
[ -z "${RNG:-}" ] && exit 0

# ---------- HOPS / POWER / RX-BOOST ----------
HP=$(dialog --stdout --no-tags --menu "Hops / TX-Power / RX-Boost" 16 76 10 \
  SAFE     "Hops=3, TX=20 dBm, RX-Boost=ON (EU-868 empfohlen)" \
  EXTENDED "Hops=5, TX=27 dBm, RX-Boost=ON (Achtung Duty-Cycle)" \
  EDGE     "Hops=6, TX=27 dBm, RX-Boost=ON (Backbone/Experimental)" \
  SKIP     "überspringen")
[ -z "${HP:-}" ] && exit 0

# ---------- DISPLAY ----------
DSP=$(dialog --stdout --no-tags --menu "Display-Timeout (Sekunden)" 14 64 6 \
  D12  "12 s" \
  D15  "15 s" \
  D20  "20 s" \
  D30  "30 s" \
  SKIP "überspringen")
[ -z "${DSP:-}" ] && exit 0

# ---------- TRANSACTION BUILD ----------
CMDS=()
CMDS+=("$MT --begin-edit")

# Region
case "$REG" in
  EU_868) CMDS+=("$MT --set lora.region EU_868");;
  EU_433) CMDS+=("$MT --set lora.region EU_433");;
  US_915) CMDS+=("$MT --set lora.region US_915");;
esac

# Rolle
case "$ROLE" in
  CLIENT|CLIENT_MUTE|ROUTER|REPEATER|TRACKER) CMDS+=("$MT --set device.role $ROLE");;
esac

# Power / Sleep
case "$PWR" in
  BAL)
    CMDS+=("$MT --set power.is_power_saving false")
    CMDS+=("$MT --set display.screen_on_secs 20")
    ;;
  LSL)
    CMDS+=("$MT --set power.is_power_saving true")
    CMDS+=("$MT --set power.ls_secs 120")
    CMDS+=("$MT --set power.min_wake_secs 15")
    CMDS+=("$MT --set power.wait_bluetooth_secs 60")
    CMDS+=("$MT --set display.screen_on_secs 12")
    ;;
  ADV)
    CMDS+=("$MT --set power.is_power_saving true")
    CMDS+=("$MT --set power.ls_secs 300")
    CMDS+=("$MT --set power.min_wake_secs 10")
    CMDS+=("$MT --set power.wait_bluetooth_secs 60")
    ;;
  EXP)
    CMDS+=("$MT --set power.is_power_saving true")
    CMDS+=("$MT --set power.ls_secs 60")
    CMDS+=("$MT --set power.min_wake_secs 5")
    CMDS+=("$MT --set power.wait_bluetooth_secs 30")
    CMDS+=("$MT --set display.screen_on_secs 8")
    ;;
esac

# Neighbor / Rebroadcast / S&F
has() { [[ " ${NETOPTS[*]} " == *" $1 "* ]]; }
$MT --help >/dev/null 2>&1 || true
$MT --help >/dev/null 2>&1 || true
has REB_ALL   && CMDS+=("$MT --set device.rebroadcast_mode ALL")
has NEIGH_ON  && CMDS+=("$MT --set neighbor_info.enabled true")
if has NEIGH_6H; then
  CMDS+=("$MT --set neighbor_info.update_interval 21600")
elif has NEIGH_4H; then
  CMDS+=("$MT --set neighbor_info.update_interval 14400")
fi
has NEIGH_LORA && CMDS+=("$MT --set neighbor_info.transmit_over_lora true")
has SAND_F     && CMDS+=("$MT --set store_forward.enabled true")
if has SAND_F_SRV; then
  CMDS+=("$MT --set store_forward.enabled true")
  CMDS+=("$MT --set store_forward.is_server true")
  CMDS+=("$MT --set store_forward.heartbeat true")
  # Optional: History limit Beispiel
  # CMDS+=("$MT --set store_forward.history_return_max 50")
fi

# Reichweite / Modem-Preset
case "$RNG" in
  STD)       CMDS+=("$MT --ch-longfast") ;;   # Shortcut für LONG_FAST
  LONGSLOW)  CMDS+=("$MT --ch-longslow") ;;   # LONG_SLOW
  VLONGSLOW) CMDS+=("$MT --ch-vlongslow") ;;  # VERY_LONG_SLOW (Experimental)
esac

# Hops / TX / RX
case "$HP" in
  SAFE)
    CMDS+=("$MT --set lora.hop_limit 3")
    CMDS+=("$MT --set lora.tx_power 20")
    CMDS+=("$MT --set lora.sx126x_rx_boosted_gain true")
    ;;
  EXTENDED)
    CMDS+=("$MT --set lora.hop_limit 5")
    CMDS+=("$MT --set lora.tx_power 27")
    CMDS+=("$MT --set lora.sx126x_rx_boosted_gain true")
    ;;
  EDGE)
    CMDS+=("$MT --set lora.hop_limit 6")
    CMDS+=("$MT --set lora.tx_power 27")
    CMDS+=("$MT --set lora.sx126x_rx_boosted_gain true")
    ;;
esac

# Display-Timeout (wenn gewählt)
case "$DSP" in
  D12) CMDS+=("$MT --set display.screen_on_secs 12");;
  D15) CMDS+=("$MT --set display.screen_on_secs 15");;
  D20) CMDS+=("$MT --set display.screen_on_secs 20");;
  D30) CMDS+=("$MT --set display.screen_on_secs 30");;
esac

CMDS+=("$MT --commit-edit")

# ---------- EXEC WITH PROGRESS ----------
{
  n=${#CMDS[@]}
  for i in "${!CMDS[@]}"; do
    pct=$(( (i*100)/n ))
    echo "$pct"; echo "### ${CMDS[$i]}"
    bash -c "${CMDS[$i]}" >>"$log" 2>&1 || true
    echo $(( ((i+1)*100)/n ))
    sleep 0.1
  done
  echo "100"; echo "Konfiguration übertragen."
  sleep 0.4
} | dialog --title "Übertrage Konfiguration" --gauge "Bitte warten..." 10 70 0

# ---------- HINWEISE ----------
warn=""
if [[ "$RNG" == "LONGSLOW" || "$RNG" == "VLONGSLOW" ]]; then
  warn+="\n• Achtung: LONG_SLOW / VERY_LONG_SLOW sind NICHT mit LONG_FAST-Netzen interoperabel und erhöhen Airtime/Latenz."
fi
if [[ "$HP" == "EXTENDED" || "$HP" == "EDGE" ]]; then
  warn+="\n• Beachte Duty-Cycle/ERP-Limits deiner Region (EU-868: bis 27 dBm ERP, 10% Duty-Cycle im 869.4–869.65 MHz Slot)."
fi
dialog --msgbox "Fertig! Du kannst den Node jetzt trennen.${warn}" 12 72
clear
