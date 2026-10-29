# Proxmox VE 9.1.6 – LXC „thomis-supercharger“

Alle Befehle auf dem **Proxmox-Host als root**. Der Container wird **angelegt, nicht gestartet**.

## 1. Vorprüfung

```bash
pveversion
pvesm status
ip -br link show vmbr0
```

Erwartet: PVE 9.1.6, Storage `local-lvm`, Bridge `vmbr0`.

## 2. Debian-13-Template und Container anlegen

Ein Block – Variablen bleiben erhalten:

```bash
set -euo pipefail

CTID=120
TEMPLATE_STORAGE=local
STORAGE=local-lvm
BRIDGE=vmbr0

# Template suchen
pveam update
TEMPLATE=$(pveam available --section system \
  | awk '/debian-13-standard_/ {print $2}' \
  | sort -V | tail -1)
[ -n "$TEMPLATE" ] || { echo "Kein Debian-13-Template gefunden"; exit 1; }
echo "Template: $TEMPLATE"

# Herunterladen, falls nötig
pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE" \
  || pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"

# Nicht überschreiben
if pct status "$CTID" >/dev/null 2>&1; then
  echo "CT $CTID existiert bereits – CTID ändern"; exit 1
fi

# Anlegen, NICHT starten
pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
  --hostname thomis-supercharger \
  --cores 2 --memory 2048 --swap 512 \
  --rootfs "${STORAGE}:16" \
  --net0 name=eth0,bridge=${BRIDGE},ip=dhcp \
  --unprivileged 1 \
  --onboot 0 \
  --ostype debian \
  --description "Thomis Supercharger – PV-Überschussladung, RFID, GUI, PDF"
```

## 3. Prüfen (ohne Start)

```bash
pct config 120
pct status 120          # muss "status: stopped" sein
```

## 4. Später starten

```bash
pct start 120
pct set 120 --onboot 1
pct exec 120 -- ip -4 -o addr show eth0
```

Die DHCP-IP steht in der Ausgabe. Danach im Router eine Reservierung setzen.

## 5. Basispakete (nur wenn gestartet)

```bash
pct exec 120 -- bash -s <<'EOF'
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
EOF
```

## 6. Optional: SSH-Key für root im Container

```bash
pct exec 120 -- mkdir -p /root/.ssh
pct exec 120 -- sh -c 'echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKeQxh85F0ixE7oY/SkgoZFS27TYQWqTWD+jTQM39YG3 thomas@ki-coding-vm" >> /root/.ssh/authorized_keys'
pct exec 120 -- chmod 700 /root/.ssh
pct exec 120 -- chmod 600 /root/.ssh/authorized_keys
```

## 7. Feste IP statt DHCP

```bash
pct set 120 --net0 name=eth0,bridge=vmbr0,ip=192.168.1.50/24,gw=192.168.1.1
pct reboot 120
```

## 8. Wenn etwas fehlt

| Meldung | Lösung |
|---|---|
| `storage 'local-lvm' does not exist` | `pvesm status` prüfen, ggf. `local-zfs` verwenden |
| `no such template` | `pveam update`, dann `pveam available --section system \| grep debian-13` |
| `CT 120 already exists` | andere CTID wählen (z. B. 121) |
| Keine DHCP-IP | `pct exec 120 -- ip a`, Bridge/VLAN prüfen |
| Netzwerkleser erreicht den LXC nicht | VLAN/Firewall, Port 1883/443 prüfen |

## 9. RFID

Gewählt ist der **Netzwerkleser ESP32 + PN532**. Kein USB-Passthrough, keine `lxc.cgroup2`-Regeln. Der Leser sendet per MQTT/HTTP an den LXC.
