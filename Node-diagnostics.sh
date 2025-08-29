#!/usr/bin/env bash
# Nadja's Node Diagnostics4Meshtastic – v0.4 (EN + rock-solid PORT init)
# Requirements: dialog, meshtastic (Python CLI)
# Usage: chmod +x nodediagnostic.sh && ./nodediagnostic.sh

set -Eeuo pipefail

APP_TITLE="Nadja's Node Diagnostics4Meshtastic"
CONF="${HOME}/.config/nd4m.conf"
mkdir -p "$(dirname "$CONF")"

# --- Hard defaults (ensure set -u safe from the very beginning) ---
PORT="/dev/ttyUSB0"
DEST=""
TELEM_TYPE="environment"
ENV_UPDATE_SECS="300"
OWNER=""
HAM_ID=""

# ===== Helpers =====
need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing dependency: $1 – please install it." >&2
    exit 1
  }
}
need dialog
need meshtastic

# Create config if missing
if [[ ! -f "$CONF" ]]; then
  cat >"$CONF" <<'EOF'
PORT=/dev/ttyUSB0
DEST=
TELEM_TYPE=environment
ENV_UPDATE_SECS=300
OWNER=
HAM_ID=
EOF
fi

# Load config + enforce defaults (never leave vars unset)
load_cfg() {
  # shellcheck disable=SC1090
  source "$CONF" 2>/dev/null || true
  : "${PORT:=/dev/ttyUSB0}"
  : "${DEST:=}"
  : "${TELEM_TYPE:=environment}"
  : "${ENV_UPDATE_SECS:=300}"
  : "${OWNER:=}"
  : "${HAM_ID:=}"
}

# Save config (write all keys)
save_cfg() {
  : "${PORT:=/dev/ttyUSB0}"
  : "${DEST:=}"
  : "${TELEM_TYPE:=environment}"
  : "${ENV_UPDATE_SECS:=300}"
  : "${OWNER:=}"
  : "${HAM_ID:=}"
  {
    echo "PORT=$PORT"
    echo "DEST=$DEST"
    echo "TELEM_TYPE=$TELEM_TYPE"
    echo "ENV_UPDATE_SECS=$ENV_UPDATE_SECS"
    echo "OWNER=$OWNER"
    echo "HAM_ID=$HAM_ID"
  } > "$CONF"
}

# Always build port args from current state
port_args() {
  echo "--port" "$PORT"
}

# Load once at startup (so menu can show $PORT safely)
load_cfg

# Progress gauge runner
run_with_gauge() {
  local title="$1"; shift
  local cmd=( "$@" )
  local outf errf
  outf="$(mktemp)"; errf="$(mktemp)"

  (
    local i=0
    while :; do
      echo $(( (i*7) % 90 + 5 ))
      echo "# Running: ${cmd[*]}"
      sleep 0.15
      i=$((i+1))
    done
  ) | dialog --title "$APP_TITLE – $title" --gauge "Starting..." 10 80 0 &
  local GAUGE_PID=$!

  set +e
  "${cmd[@]}" >"$outf" 2>"$errf"
  local rc=$?
  set -e

  if kill -0 "$GAUGE_PID" 2>/dev/null; then
    kill "$GAUGE_PID" >/dev/null 2>&1 || true
    wait "$GAUGE_PID" 2>/dev/null || true
  fi

  if (( rc == 0 )); then
    if [[ -s "$outf" ]]; then
      dialog --title "$title – OK" --textbox "$outf" 22 100
    else
      dialog --title "$title – OK" --msgbox "Done." 7 40
    fi
  else
    {
      echo "Command:"
      printf '  %q ' "${cmd[@]}"
      echo -e "\n\nExit code: $rc"
      echo -e "\n--- STDOUT ---"
      cat "$outf"
      echo -e "\n--- STDERR ---"
      cat "$errf"
    } >"$errf.full"
    dialog --title "$title – Error" --textbox "$errf.full" 22 100
  fi

  rm -f "$outf" "$errf" "$errf.full" 2>/dev/null || true
  return $rc
}

# ===== Actions =====
set_port() {
  load_cfg
  local new
  new=$(dialog --title "$APP_TITLE – Set Serial Port" \
               --inputbox "Enter serial port (e.g. /dev/ttyUSB0)" 10 60 "$PORT" 3>&1 1>&2 2>&3) || return
  PORT="$new"; save_cfg
}

show_info()  { load_cfg; run_with_gauge "Node Info" meshtastic $(port_args) --info; }
list_nodes() { load_cfg; run_with_gauge "Nodes"     meshtastic $(port_args) --nodes; }

show_qr() {
  load_cfg
  local choice
  choice=$(dialog --title "$APP_TITLE – QR" --menu "Show QR" 12 60 2 \
    1 "Primary Channel (QR)" \
    2 "All Channels (QR-All)" 3>&1 1>&2 2>&3) || return
  if [[ "$choice" == "1" ]]; then
    run_with_gauge "QR Primary" meshtastic $(port_args) --qr
  else
    run_with_gauge "QR All" meshtastic $(port_args) --qr-all
  fi
}

set_channel_url() {
  load_cfg
  local url
  url=$(dialog --title "$APP_TITLE – Set Channel URL" \
               --inputbox "Paste Meshtastic channel URL (psk, region, modem…)" 10 70 "" 3>&1 1>&2 2>&3) || return
  [[ -n "$url" ]] || return
  run_with_gauge "Set Channel URL" meshtastic $(port_args) --ch-set-url "$url"
}

channel_presets() {
  load_cfg
  local p
  p=$(dialog --title "$APP_TITLE – Modem Preset" --menu "Choose preset" 14 56 6 \
    longslow     "Long range, slow" \
    longfast     "Long range, faster" \
    medslow      "Medium, slow" \
    medfast      "Medium, faster" \
    shortslow    "Short, slow" \
    shortfast    "Short, faster" 3>&1 1>&2 2>&3) || return
  run_with_gauge "Preset: $p" meshtastic $(port_args) --ch-"$p"
}

owner_set() {
  load_cfg
  local name
  name=$(dialog --title "$APP_TITLE – Set Owner" --inputbox "Owner/display name" 10 60 "$OWNER" 3>&1 1>&2 2>&3) || return
  OWNER="$name"; save_cfg
  run_with_gauge "Set Owner" meshtastic $(port_args) --set-owner "$name"
}

owner_short_set() {
  load_cfg
  local name
  name=$(dialog --title "$APP_TITLE – Set Short Owner" --inputbox "Short name (~4–6 chars)" 10 60 "" 3>&1 1>&2 2>&3) || return
  run_with_gauge "Set Short Owner" meshtastic $(port_args) --set-owner-short "$name"
}

ham_id_set() {
  load_cfg
  local id
  id=$(dialog --title "$APP_TITLE – Set HAM ID" --inputbox "Amateur radio callsign (disables encryption)" 10 60 "$HAM_ID" 3>&1 1>&2 2>&3) || return
  HAM_ID="$id"; save_cfg
  run_with_gauge "Set HAM ID" meshtastic $(port_args) --set-ham "$id"
}

fixed_position() {
  load_cfg
  local lat lon alt
  lat=$(dialog --title "$APP_TITLE – Fixed Position" --inputbox "Latitude (decimal)" 9 50 "" 3>&1 1>&2 2>&3) || return
  lon=$(dialog --title "$APP_TITLE – Fixed Position" --inputbox "Longitude (decimal)" 9 50 "" 3>&1 1>&2 2>&3) || return
  alt=$(dialog --title "$APP_TITLE – Fixed Position" --inputbox "Altitude (meters)" 9 50 "0" 3>&1 1>&2 2>&3) || return
  run_with_gauge "Set Fixed Position" meshtastic $(port_args) --setlat "$lat" --setlon "$lon" --setalt "$alt"
}

clear_position() { load_cfg; run_with_gauge "Clear Fixed Position" meshtastic $(port_args) --remove-position; }

export_config() {
  load_cfg
  local path
  path=$(dialog --title "$APP_TITLE – Export Config" --fselect "$HOME/" 14 70 3>&1 1>&2 2>&3) || return
  [[ -n "$path" ]] || return
  run_with_gauge "Export Config" meshtastic $(port_args) --export-config "$path"
}

import_config() {
  load_cfg
  local path
  path=$(dialog --title "$APP_TITLE – Import Config (YAML)" --fselect "$HOME/" 14 70 3>&1 1>&2 2>&3) || return
  [[ -n "$path" ]] || return
  run_with_gauge "Import Config" meshtastic $(port_args) --configure "$path"
}

choose_dest() {
  load_cfg
  local id
  id=$(dialog --title "$APP_TITLE – Destination Node" \
              --inputbox "Destination Node ID (!xxxxxxxx). Empty = broadcast." 10 60 "$DEST" 3>&1 1>&2 2>&3) || return
  DEST="$id"; save_cfg
}

send_text() {
  load_cfg
  local text
  text=$(dialog --title "$APP_TITLE – Send Text" --inputbox "Message (broadcast or use 'Choose destination')" 10 70 "" 3>&1 1>&2 2>&3) || return
  if [[ -n "$DEST" ]]; then
    run_with_gauge "Send Text (dest=$DEST)" meshtastic $(port_args) --dest "$DEST" --sendtext "$text" --ack
  else
    run_with_gauge "Send Text (broadcast)"  meshtastic $(port_args) --sendtext "$text" --ack
  fi
}

request_telemetry() {
  load_cfg
  local t
  t=$(dialog --title "$APP_TITLE – Request Telemetry" --menu "Which telemetry?" 14 60 5 \
     environment "Environment (temp/humidity…)" \
     device      "Device (battery…)" \
     health      "Health" \
     air_quality "Air quality" \
     all         "All available" 3>&1 1>&2 2>&3) || return
  TELEM_TYPE="$t"; save_cfg

  if [[ -n "$DEST" ]]; then
    run_with_gauge "Telemetry $t (dest=$DEST)" meshtastic $(port_args) --dest "$DEST" --request-telemetry "$t"
  else
    run_with_gauge "Telemetry $t (local)"      meshtastic $(port_args) --request-telemetry "$t"
  fi
}

request_position() {
  load_cfg
  if [[ -z "$DEST" ]]; then
    dialog --title "$APP_TITLE" --msgbox "Please set a destination first (menu: Choose destination)." 8 60
    return
  fi
  run_with_gauge "Request Position" meshtastic $(port_args) --dest "$DEST" --request-position
}

device_time_now() { load_cfg; run_with_gauge "Set Device Time (now)" meshtastic $(port_args) --set-time; }

traceroute() {
  load_cfg
  if [[ -z "$DEST" ]]; then
    dialog --title "$APP_TITLE" --msgbox "Please set a destination first (menu: Choose destination)." 8 60
    return
  fi
  run_with_gauge "Traceroute → $DEST" meshtastic $(port_args) --traceroute "$DEST"
}

admin_actions() {
  load_cfg
  local c
  c=$(dialog --title "$APP_TITLE – Admin" --menu "Action (affects local or DEST)" 14 60 5 \
     reboot       "Reboot" \
     shutdown     "Shutdown" \
     factory_conf "Factory reset (config)" \
     factory_all  "Factory reset (device + bonds)" \
     device_meta  "Device metadata" 3>&1 1>&2 2>&3) || return
  case "$c" in
    reboot)       run_with_gauge "Reboot"              meshtastic $(port_args) ${DEST:+--dest "$DEST"} --reboot ;;
    shutdown)     run_with_gauge "Shutdown"            meshtastic $(port_args) ${DEST:+--dest "$DEST"} --shutdown ;;
    factory_conf) run_with_gauge "Factory reset (cfg)" meshtastic $(port_args) ${DEST:+--dest "$DEST"} --factory-reset ;;
    factory_all)  run_with_gauge "Factory reset (all)" meshtastic $(port_args) ${DEST:+--dest "$DEST"} --factory-reset-device ;;
    device_meta)  run_with_gauge "Device metadata"     meshtastic $(port_args) ${DEST:+--dest "$DEST"} --device-metadata ;;
  esac
}

telemetry_enable_screen() {
  load_cfg
  run_with_gauge "Enable Env Screen (local)" meshtastic $(port_args) \
    --set telemetry.environment_measurement_enabled true \
    --set telemetry.environment_update_interval "$ENV_UPDATE_SECS" \
    --set telemetry.environment_screen_enabled true
}

telemetry_set_interval() {
  load_cfg
  local sec
  sec=$(dialog --title "$APP_TITLE – Telemetry Interval" --inputbox "Seconds (e.g. 300)" 9 50 "$ENV_UPDATE_SECS" 3>&1 1>&2 2>&3) || return
  ENV_UPDATE_SECS="$sec"; save_cfg
  run_with_gauge "Set telemetry interval" meshtastic $(port_args) --set telemetry.environment_update_interval "$sec"
}

generic_set() {
  load_cfg
  local field val
  field=$(dialog --title "$APP_TITLE – Generic --set" --inputbox "Field (e.g. device.role)" 9 60 "" 3>&1 1>&2 2>&3) || return
  val=$(dialog --title "$APP_TITLE – Generic --set" --inputbox "Value (true/false/number/string)" 9 60 "" 3>&1 1>&2 2>&3) || return
  run_with_gauge "Set $field=$val" meshtastic $(port_args) --set "$field" "$val"
}

show_fields_nodes() {
  load_cfg
  local fields
  fields=$(dialog --title "$APP_TITLE – Nodes w/ Fields" --inputbox "Comma-separated (e.g. longName,shortName,battery)" 10 70 "longName,shortName,battery" 3>&1 1>&2 2>&3) || return
  run_with_gauge "Nodes (show fields)" meshtastic $(port_args) --nodes --show-fields "$fields"
}

# ===== Main menu =====
main_menu() {
  while true; do
    load_cfg
    local choice
    choice=$(dialog --title "$APP_TITLE" --menu "Port: $PORT  |  DEST: ${DEST:-Broadcast}" 22 84 20 \
      p "Set serial port" \
      i "Show node info" \
      n "List nodes" \
      q "Show QR code" \
      u "Set channel URL" \
      m "Select modem preset" \
      o "Set owner" \
      O "Set short owner" \
      h "Set HAM ID (unencrypted)" \
      f "Set fixed position" \
      F "Clear fixed position" \
      e "Enable env telemetry screen (local)" \
      I "Set telemetry interval" \
      T "Request telemetry (local/DEST)" \
      P "Request position (DEST)" \
      d "Choose destination (!xxxxxxxx)" \
      s "Send text (broadcast/DEST)" \
      t "Traceroute (DEST)" \
      a "Admin actions (reboot/factory…)" \
      x "Export config" \
      c "Import config (YAML)" \
      g "Generic --set" \
      S "Set device time (now)" \
      z "Nodes with fields" \
      X "Exit" 3>&1 1>&2 2>&3) || break

    case "$choice" in
      p) set_port ;;
      i) show_info ;;
      n) list_nodes ;;
      q) show_qr ;;
      u) set_channel_url ;;
      m) channel_presets ;;
      o) owner_set ;;
      O) owner_short_set ;;
      h) ham_id_set ;;
      f) fixed_position ;;
      F) clear_position ;;
      e) telemetry_enable_screen ;;
      I) telemetry_set_interval ;;
      T) request_telemetry ;;
      P) request_position ;;
      d) choose_dest ;;
      s) send_text ;;
      t) traceroute ;;
      a) admin_actions ;;
      x) export_config ;;
      c) import_config ;;
      g) generic_set ;;
      S) device_time_now ;;
      z) show_fields_nodes ;;
      X) break ;;
    esac
  done
}

main_menu
