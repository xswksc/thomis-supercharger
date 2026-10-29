# Thomis Supercharger

Konzept und Unterlagen für eine intelligente PV-Überschussladung mit Tesla, SolarEdge, go-e oder SolarEdge-Wallbox, RFID-Benutzerverwaltung, SvelteKit-GUI und PDF-Monatsbericht.

## Inhalt

- [Gesamtkonzept](Thomis_Supercharger_Vorschlag.md) – Architektur, Regelung, RFID, GUI, Auswertung, Proxmox, Kosten und Risiken
- [Proxmox-Befehle](Proxmox_Befehle.md) – Copy-paste-Befehle für PVE 9.1.6
- [Installations-Textdatei](Proxmox_Installation.txt) – LXC anlegen, nicht starten
- [LXC-Installer](proxmox_lxc_setup.sh) – `START=0` legt den Container nur an
- [evcc-Basiskonfiguration](evcc-baseline.yaml) – SolarEdge, go-e, optional Shelly
- [Architektur](Architektur_Ueberschussladung.png)
- [Dashboard-Mockup](GUI_Dashboard.png)
- [Auswertungs-Mockup](GUI_Auswertung.png)
- [PDF-Monatsbericht](Monatsbericht_2026-10.pdf)

## Schnellstart Proxmox

```bash
bash proxmox_lxc_setup.sh
```

Standard: `local-lvm`, `vmbr0`, DHCP, `START=0` – der Container wird angelegt, aber nicht gestartet.

## Status

Planungsstand. Die GUI- und PDF-Dateien sind Mockups; die Software wird daraus noch umgesetzt.
