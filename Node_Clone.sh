#!/usr/bin/env bash
# Nadjas Node Flasher - Meshtastic version 0.1
# Menü-gesteuertes Tool zum Sichern & Klonen von Meshtastic-Settings
# Abhängigkeiten: dialog, meshtastic (CLI), coreutils, base64, (xxd oder hexdump)
# Tested on: Ubuntu/KDE

set -Eeuo pipefail

VERSION="0.1"
TITLE="Nadjas Node Flasher - Meshtastic version ${VERSION}"

# ====== Default-Pfade & Variablen ======
SAVE_DIR="${HOME}/meshtastic_configs"
CONFIG_FILE="${SAVE_DIR}/node.latest.yaml"      # eine "aktuelle" Datei
LOGFILE="${SAVE_DIR}/last_run.log"
STATUS_FILE="${SAVE_DIR}/.cmd_status"

# Aktiver Port (per Menü anpassbar)
PORT="/dev/ttyUSB0"

# ====== Fix-Einstellungen (togglbar im Menü) ======
LOCK_ROLE=1
LOCK_CH_NAME=1
LOCK_PSK=1

ROLE_VALUE="Client"         # device.role
PRIMARY_CH_INDEX=0          # primärer Channel = 0
PRIMARY_CH_NAME="Space"
PRIMARY_PSK_B64="YjBid1JrdjRWYnowaDVoNw=="

# ====== Hilfsfunktionen ======
need() {
  command -v "$1" >/dev/null 2>&1 || {
    dialog --backtitle "$TITLE" --msgbox "Fehlende Abhängigkeit: $1\nBitte installieren und erneut starten." 8 60
    exit 1
  }
}

ensure_dirs() {
  mkdir -p "$SAVE_DIR"
  : >"$LOGFILE"
}

press_anykey() {
  echo
  read -r -n1 -s -p "Weiter mit einer beliebigen Taste ..." _any
}

b64_to_hex() {
  # Base64 -> hex mit 0x-Präfix (für --ch-set psk erwartet die CLI Hex-Format)
  local b64="$1"
  local raw
  if ! raw="$(printf '%s' "$b64" | base64 -d 2>/dev/null)"; then
    return 1
  fi
  if command -v xxd >/dev/null 2>&1; then
    printf '0x%s' "$(printf '%s' "$raw" | xxd -p -c 256)"
  else
    printf '0x%s' "$(printf '%s' "$raw" | hexdump -v -e '/1 "%02x"')"
  fi
}

run_cmd_gauge() {
  # Nutzt dialog --gauge als "coole" Progressbar während ein Kommando läuft
  # Speichert Exit-Code des Kommandos in $STATUS_FILE
  local msg="$1"; shift
  : >"$STATUS_FILE"
  {
    echo 5
    ("$@" >>"$LOGFILE" 2>&1)
    echo $? >"$STATUS_FILE"
    echo 100
  } | dialog --backtitle "$TITLE" --title "Arbeite..." --gauge "$msg" 9 70 0
  local st=0
  if [[ -s "$STATUS_FILE" ]]; then
    st="$(cat "$STATUS_FILE")"
  fi
  return "$st"
}

choose_port() {
  # Liste gängige Ports + "Manuell eingeben"
  local entries=()
  local found=0
  for p in /dev/ttyUSB* /dev/ttyACM*; do
    if [[ -e "$p" ]]; then
      entries+=("$p" "Serieller Port")
      found=1
    fi
  done
  entries+=("MANUAL" "Port manuell eingeben")

  local choice
  choice=$(dialog --backtitle "$TITLE" --no-tags --stdout --menu "Port auswählen" 12 60 12 "${entries[@]}") || return 1

  if [[ "$choice" == "MANUAL" ]]; then
    local manual
    manual=$(dialog --backtitle "$TITLE" --stdout --inputbox "Port eingeben (z.B. /dev/ttyUSB0)" 8 60 "$PORT") || return 1
    PORT="$manual"
  else
    PORT="$choice"
  fi
}

confirm_port_or_set() {
  if [[ ! -e "$PORT" ]]; then
    dialog --backtitle "$TITLE" --yesno "Aktueller Port:\n${PORT}\n\nNicht gefunden. Jetzt einstellen?" 9 60
    if [[ $? -eq 0 ]]; then
      choose_port || return 1
    else
      return 1
    fi
  fi
}

edit_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    dialog --backtitle "$TITLE" --msgbox "Noch keine Konfigdatei vorhanden.\nBitte zuerst 'Read Node' ausführen." 8 60
    return
  fi
  ${EDITOR:-nano} "$CONFIG_FILE"
}

toggle_locks_menu() {
  while true; do
    local role_state chname_state psk_state
    role_state=$([ "$LOCK_ROLE" -eq 1 ] && echo "ON" || echo "OFF")
    chname_state=$([ "$LOCK_CH_NAME" -eq 1 ] && echo "ON" || echo "OFF")
    psk_state=$([ "$LOCK_PSK" -eq 1 ] && echo "ON" || echo "OFF")

    local choice
    choice=$(dialog --backtitle "$TITLE" --stdout --menu "Fix-Einstellungen" 14 70 8 \
      "1" "Rolle fixieren: ${role_state} (aktuell: ${ROLE_VALUE})" \
      "2" "Primärer Channel-Name fixieren: ${chname_state} (aktuell: ${PRIMARY_CH_NAME})" \
      "3" "Primärer PSK fixieren: ${psk_state} (Base64 gesetzt)" \
      "4" "Wert ändern: Rolle" \
      "5" "Wert ändern: Channel-Name" \
      "6" "Wert ändern: PSK (Base64)" \
      "7" "Channel-Index (primär=0) ändern (aktuell: ${PRIMARY_CH_INDEX})" \
      "q" "Zurück") || break

    case "$choice" in
      1) LOCK_ROLE=$((1-LOCK_ROLE));;
      2) LOCK_CH_NAME=$((1-LOCK_CH_NAME));;
      3) LOCK_PSK=$((1-LOCK_PSK));;
      4)
        local nv
        nv=$(dialog --backtitle "$TITLE" --stdout --inputbox "Neuer Rollenwert (z.B. Client, Repeater ...)" 8 60 "$ROLE_VALUE") && ROLE_VALUE="$nv"
        ;;
      5)
        local nv
        nv=$(dialog --backtitle "$TITLE" --stdout --inputbox "Neuer Channel-Name" 8 60 "$PRIMARY_CH_NAME") && PRIMARY_CH_NAME="$nv"
        ;;
      6)
        local nv
        nv=$(dialog --backtitle "$TITLE" --stdout --inputbox "Neuer PSK (Base64, 128-bit=16 Bytes)" 8 60 "$PRIMARY_PSK_B64") && PRIMARY_PSK_B64="$nv"
        ;;
      7)
        local nv
        nv=$(dialog --backtitle "$TITLE" --stdout --inputbox "Channel-Index (0=Primary)" 8 60 "$PRIMARY_CH_INDEX") && PRIMARY_CH_INDEX="$nv"
        ;;
      q) break;;
    esac
  done
}

apply_invariants() {
  local tgt_port="$1"
  local had_err=0

  if [[ "$LOCK_ROLE" -eq 1 ]]; then
    if ! run_cmd_gauge "Setze Rolle: ${ROLE_VALUE}" meshtastic --port "$tgt_port" --set device.role "$ROLE_VALUE"; then
      had_err=1
    fi
  fi

  if [[ "$LOCK_CH_NAME" -eq 1 ]]; then
    if ! run_cmd_gauge "Setze Channel-Name: ${PRIMARY_CH_NAME}" \
         meshtastic --port "$tgt_port" --ch-set name "$PRIMARY_CH_NAME" --ch-index "$PRIMARY_CH_INDEX"; then
      had_err=1
    fi
  fi

  if [[ "$LOCK_PSK" -eq 1 ]]; then
    local keyhex
    if ! keyhex="$(b64_to_hex "$PRIMARY_PSK_B64")" || [[ -z "$keyhex" || "$keyhex" == "0x" ]]; then
      dialog --backtitle "$TITLE" --msgbox "PSK-Konvertierung fehlgeschlagen. Bitte Base64 prüfen." 8 60
      had_err=1
    else
      if ! run_cmd_gauge "Setze PSK für Channel ${PRIMARY_CH_INDEX}" \
           meshtastic --port "$tgt_port" --ch-set psk "$keyhex" --ch-index "$PRIMARY_CH_INDEX"; then
        had_err=1
      fi
    fi
  fi

  return "$had_err"
}

read_node() {
  confirm_port_or_set || return
  ensure_dirs

  local timestamped="${SAVE_DIR}/node.$(date +%Y%m%d-%H%M%S).yaml"
  : >"$LOGFILE"

  if run_cmd_gauge "Lese Config von ${PORT} ..." meshtastic --port "$PORT" --export-config "$timestamped"; then
    cp -f "$timestamped" "$CONFIG_FILE"
    dialog --backtitle "$TITLE" --msgbox "Konfiguration erfolgreich gesichert:\n${CONFIG_FILE}" 8 70
  else
    dialog --backtitle "$TITLE" --msgbox "Fehler beim Auslesen.\nSiehe Log:\n$LOGFILE" 8 70
  fi
  press_anykey
}

write_node() {
  confirm_port_or_set || return
  ensure_dirs
  if [[ ! -f "$CONFIG_FILE" ]]; then
    dialog --backtitle "$TITLE" --msgbox "Keine gespeicherte Konfig gefunden:\n${CONFIG_FILE}\nBitte zuerst 'Read Node' ausführen." 9 70
    return
  fi
  : >"$LOGFILE"

  # 1) Gesamte YAML-Konfig auf Ziel schreiben
  if ! run_cmd_gauge "Schreibe gespeicherte Settings -> ${PORT} ..." meshtastic --port "$PORT" --configure "$CONFIG_FILE"; then
    dialog --backtitle "$TITLE" --msgbox "Fehler beim Schreiben.\nSiehe Log:\n$LOGFILE" 8 70
    press_anykey
    return
  fi

  # 2) Fix-Einstellungen erzwingen (Rolle, Channel-Name, PSK)
  if apply_invariants "$PORT"; then
    dialog --backtitle "$TITLE" --msgbox "Clonen abgeschlossen.\nPort: ${PORT}\nQuelle: ${CONFIG_FILE}" 8 70
  else
    dialog --backtitle "$TITLE" --msgbox "Clonen abgeschlossen (mit Warnungen).\nBitte Log prüfen:\n$LOGFILE" 9 70
  fi
  press_anykey
}

about_box() {
  dialog --backtitle "$TITLE" --msgbox \
"$(printf '%s\n\n%s\n%s\n\n%s\n%s\n' \
  "$TITLE" \
  "Funktionen:" \
  "• Read Node: exportiert YAML des angeschlossenen Nodes." \
  "• Write Data2Node: schreibt YAML auf Ziel-Node und erzwingt (optional) Rolle/Channel/PSK." \
  "Hinweis: Schließe andere Tools (z.B. WebApp/Serial-Monitore), falls der Port 'busy' ist." \
)" 12 70
}

# ====== Start-Checks ======
need dialog
need meshtastic
need base64
if ! command -v xxd >/dev/null 2>&1 && ! command -v hexdump >/dev/null 2>&1; then
  dialog --backtitle "$TITLE" --msgbox "Weder 'xxd' noch 'hexdump' gefunden.\nBitte eines davon installieren (z.B. 'sudo apt install xxd')." 9 70
  exit 1
fi
ensure_dirs

# ====== Hauptmenü ======
while true; do
  status="Port: ${PORT}\nConfig: ${CONFIG_FILE}"
  choice=$(dialog --backtitle "$TITLE" --stdout --menu "$status" 16 72 10 \
    "1" "Read Node – Einstellungen auslesen & speichern" \
    "2" "Write Data2Node – Einstellungen auf Ziel-Node schreiben" \
    "3" "Port wählen/ändern" \
    "4" "Fix-Einstellungen (Rolle/Channel/PSK) anpassen" \
    "5" "Gespeicherte Konfig mit Nano bearbeiten" \
    "6" "Über / Hilfe" \
    "q" "Beenden") || break

  case "$choice" in
    1) read_node;;
    2) write_node;;
    3) choose_port || true;;
    4) toggle_locks_menu;;
    5) edit_config;;
    6) about_box;;
    q) break;;
  esac
done

clear
echo "$TITLE - beendet."
