# Ubuntu 24.04 LTS Declarative Templates & Field Staging Kit

This directory contains ready-to-copy templates for preparing Ubuntu 24.04 LTS machines for OSCAR
across off-site hotel-room staging, bare-metal USB installs, and completely air-gapped sites with
no internet or DHCP.

For the complete step-by-step field manual (written for users with no prior Ubuntu or OSCAR
experience, including USB installer links and unknown camera/RPM discovery), read
[UBUNTU_FIELD_SETUP_GUIDE.md](../../../docs/UBUNTU_FIELD_SETUP_GUIDE.md).

## Contents

| File | When to Use |
| --- | --- |
| `create-autoinstall-usb.sh` & `create-autoinstall-usb.ps1` | One-command bare-metal Ubuntu 24.04 autoinstall USB builder for **Ubuntu** (`sudo bash oscar.sh create-autoinstall-usb`) and **Windows 11** (`.\oscar.bat create-autoinstall-usb`). Writes the Ubuntu 24.04 Live Server ISO, `CIDATA` profile (with USB-NVMe stability quirks, optional `--luks-passphrase-file` / `-LuksPassphraseFile` LUKS2 full-disk encryption, `--require-sudo-password`, and `--ssh-keys-only` SSH hardening), `OSCAR_MEDIA` offline bundle, and optional `seed/` imports onto a single external USB drive while strictly protecting internal OS and `OSCAR_BACKUP` disks. |
| `oscar-firstboot-wizard.sh` | Interactive post-autoinstall provisioning & recovery TUI (`sudo bash oscar.sh wizard` / `sudo oscar-wizard`, auto-launched on first login): optimizes the Ubuntu host offline, mounts attached USB drives read-only (`-o ro`), and lets the administrator choose USB NVMe Backup Restore, Single-Snapshot Restore, Fresh Install + `config.json` / `lanes.csv` / `.pmtiles` Import, or Clean Site Init. |
| `site-network.example.env` | Simple fill-in-the-blanks worksheet for staging site static IPs in a hotel room (`sudo bash oscar.sh stage-site-network --config ubuntu/site-network.env`) without dropping hotel Wi-Fi/DHCP. |
| `netplan/01-single-nic-static.yaml.example` | Netplan v2 template when Operator PCs, RPMs, and cameras share a single Ethernet switch (with or without a default gateway). |
| `netplan/02-dual-nic-operator-and-sensor-vlan.yaml.example` | Netplan v2 template for 2-NIC portal servers: Port 1 = Operator/Site LAN, Port 2 = Isolated air-gapped RPM & camera switch (`optional: true`, no gateway). |
| `autoinstall/user-data.yaml` & `autoinstall/meta-data` | Zero-touch declarative Ubuntu Server 24.04 `cloud-init` installer config (`CIDATA` USB label or PXE): allocates `100%` of the NVMe (`sizing-policy: all`), skips Snap Docker, enables SSH, and prevents offline boot hangs. |
| `ansible-site-hosts.yml` | Optional single-file Ansible playbook to converge one or multiple Ubuntu 24.04 hosts remotely over SSH from a laptop. |
