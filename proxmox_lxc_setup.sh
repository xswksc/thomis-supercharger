#!/usr/bin/env bash
#
# Thomis Supercharger – LXC-Installer für Proxmox VE 9.x
#
# Auf dem Proxmox-Host als root ausführen:
#   bash proxmox_lxc_setup.sh
#
# Vorher die CONFIG unten anpassen (Storage, Bridge, VLAN, IP).
# Das Skript legt einen unprivilegierten Debian-13-LXC an.
# Standard: nur anlegen, NICHT starten. Mit START=1 wird gestartet
# und die Basispakete werden installiert.
#
set -euo pipefail

# ----------------------------- CONFIG -----------------------------
CTID="${CTID:-120}"
HOSTNAME="${HOSTNAME:-thomis-supercharger}"

STORAGE="${STORAGE:-local-lvm}"        # gewählt: local-lvm
DISK_GB="${DISK_GB:-16}"
CORES="${CORES:-2}"
MEMORY_MB="${MEMORY_MB:-2048}"
SWAP_MB="${SWAP_MB:-512}"

BRIDGE="${BRIDGE:-vmbr0}"
VLAN="${VLAN:-}"                       # z. B. 20; leer = kein VLAN-Tag
IP_CIDR="${IP_CIDR:-dhcp}"             # dhcp oder z. B. 192.168.1.50/24
GATEWAY="${GATEWAY:-}"                 # nur bei statischer IP nötig

TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-}" # optional: /root/.ssh/authorized_keys

START="${START:-0}"                    # 0 = nur anlegen, 1 = starten + Pakete
ONBOOT="${ONBOOT:-0}"                  # 1 = beim Host-Boot automatisch starten
# ------------------------------------------------------------------

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mFEHLER: %s\033[0m\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || fail "Bitte als root auf dem Proxmox-Host ausführen."
command -v pct   >/dev/null 2>&1 || fail "pct nicht gefunden – ist das ein Proxmox-Host?"
command -v pveam >/dev/null 2>&1 || fail "pveam nicht gefunden – ist das ein Proxmox-Host?"
command -v pvesm >/dev/null 2>&1 || fail "pvesm nicht gefunden – ist das ein Proxmox-Host?"

log "Proxmox-Version"
pveversion | head -1

if pct status "${CTID}" >/dev/null 2>&1; then
  fail "Container ${CTID} existiert bereits. CTID ändern oder alten Container entfernen."
fi

log "Storage prüfen: ${STORAGE}"
pvesm status --storage "${STORAGE}" >/dev/null 2>&1 \
  || fail "Storage '${STORAGE}' nicht gefunden. pvesm status zeigt die verfügbaren Storages."

log "Debian-13-Template suchen"
pveam update >/dev/null
TEMPLATE="$(pveam available --section system \
  | awk '$2 ~ /^debian-13-standard_/ {print $2}' \
  | sort -V | tail -1)"

[[ -n "${TEMPLATE}" ]] || fail "Kein Debian-13-Template verfügbar. pveam available --section system prüfen."

log "Template: ${TEMPLATE}"
if ! pveam list "${TEMPLATE_STORAGE}" | grep -q "${TEMPLATE}"; then
  log "Template herunterladen nach ${TEMPLATE_STORAGE}"
  pveam download "${TEMPLATE_STORAGE}" "${TEMPLATE}"
fi

TEMPLATE_PATH="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"

NET="name=eth0,bridge=${BRIDGE},ip=${IP_CIDR}"
if [[ -n "${VLAN}" ]]; then
  NET="name=eth0,bridge=${BRIDGE},tag=${VLAN},ip=${IP_CIDR}"
fi
if [[ "${IP_CIDR}" != "dhcp" ]]; then
  [[ -n "${GATEWAY}" ]] || fail "GATEWAY fehlt für die statische IP ${IP_CIDR}."
  NET+=",gw=${GATEWAY}"
fi

log "Container ${CTID} anlegen"
ARGS=(
  create "${CTID}" "${TEMPLATE_PATH}"
  --hostname "${HOSTNAME}"
  --cores "${CORES}"
  --memory "${MEMORY_MB}"
  --swap "${SWAP_MB}"
  --rootfs "${STORAGE}:${DISK_GB}"
  --net0 "${NET}"
  --unprivileged 1
  --onboot "${ONBOOT}"
  --ostype debian
  --description "Thomis Supercharger – PV-Überschussladung, RFID, GUI, PDF"
)
if [[ -n "${SSH_PUBKEY_FILE}" && -f "${SSH_PUBKEY_FILE}" ]]; then
  ARGS+=(--ssh-public-keys "${SSH_PUBKEY_FILE}")
fi
pct "${ARGS[@]}"

if [[ "${START}" == "1" ]]; then
  log "Container starten"
  pct start "${CTID}"

  log "Netzwerk abwarten"
  for _ in $(seq 1 30); do
    if pct exec "${CTID}" -- getent hosts deb.debian.org >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  pct exec "${CTID}" -- getent hosts deb.debian.org >/dev/null 2>&1 \
    || fail "Kein DNS/Internet im Container. Netzwerk, VLAN und Gateway prüfen."

  log "Basispakete installieren"
  pct exec "${CTID}" -- bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade
apt-get install -y --no-install-recommends \
  curl ca-certificates gnupg git jq unzip sudo \
  sqlite3 python3 python3-venv python3-pip \
  caddy chrony \
  libpango-1.0-0 libpangoft2-1.0-0 libcairo2 libgdk-pixbuf-2.0-0 \
  fonts-dejavu shared-mime-info
timedatectl set-timezone Europe/Berlin || true
systemctl enable --now chrony || true
systemctl disable --now caddy 2>/dev/null || true
install -d -m 0755 /opt/thomis-supercharger /var/lib/thomis-supercharger /var/backups/thomis
'

  log "IP-Adresse ermitteln"
  CT_IP=""
  for _ in $(seq 1 30); do
    CT_IP="$(pct exec "${CTID}" -- ip -4 -o addr show dev eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1 || true)"
    [[ -n "${CT_IP}" ]] && break
    sleep 1
  done
  STATUS="gestartet"
  START_HINT="pct enter ${CTID}"
else
  log "Container angelegt – nicht gestartet"
  CT_IP=""
  STATUS="gestoppt"
  START_HINT="pct start ${CTID}
pct enter ${CTID}"
fi

log "Fertig"
cat <<EOF

Container ${CTID} (${HOSTNAME}) ist ${STATUS}.
  IP:        ${CT_IP:-${IP_CIDR}}
  Storage:   ${STORAGE} (${DISK_GB} GB)
  Template:  ${TEMPLATE}
  Autostart: ${ONBOOT}

Nächste Schritte:
${START_HINT}
  # evcc installieren, App nach /opt/thomis-supercharger, Caddy konfigurieren

RFID: Netzwerkleser (ESP32 + PN532) – kein USB-Passthrough nötig.

Hinweis: Für Docker im LXC zusätzlich
  pct set ${CTID} --features nesting=1,keyctl=1
EOF
