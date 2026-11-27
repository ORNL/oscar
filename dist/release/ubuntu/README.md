# Ubuntu 24.04 LTS Declarative Templates & Bare-Metal Autoinstall USB Creator

This directory contains the cross-platform **OSCAR Bare-Metal Ubuntu 24.04 Offline Autoinstall USB Creator** (**GUI + TUI + CLI** for both **Windows 11** and **Ubuntu**) along with declarative templates for off-site staging, bare-metal USB installs, and completely air-gapped sites with no internet or DHCP.

For the complete step-by-step field manual (written for users with no prior Ubuntu or OSCAR experience, including USB installer links and unknown camera/RPM discovery), read [UBUNTU_FIELD_SETUP_GUIDE.md](../../../docs/UBUNTU_FIELD_SETUP_GUIDE.md).

## Quick Start (Standalone `oscar-*-autoinstall-usb-creator.zip` or Bundled `ubuntu/`)

1. Download **`oscar-*-ubuntu-x86_64-offline-full.zip`** (leave it zipped) and **`ubuntu-24.04.x-live-server-amd64.iso`** into your `Downloads` folder (or the same folder as this kit).
2. Insert a **16+ GiB external USB flash drive or USB SSD** (internal OS drives and `OSCAR_BACKUP` drives are automatically hidden and protected).
3. Launch your preferred interface:
   - **Windows 11 Desktop GUI:** Double-click **`create-autoinstall-usb.bat`** (auto-elevates via UAC and opens the native Windows GUI).
   - **Windows 11 Terminal TUI:** Run `.\create-autoinstall-usb.bat -Tui` from an Administrator PowerShell/Command Prompt.
   - **Windows 11 Scripted CLI:** Run `.\create-autoinstall-usb.ps1 -IsoPath ... -OfflineBundlePath ... -DiskNumber 2 -Hostname oscar-host -Username oscaradmin -PasswordFile ... -RequireSudoPassword -OscarAdminPasswordFile ... -LanesFile lanes.csv -AutoInitOscar -ConfirmToken ERASE-USB`.
   - **Ubuntu Desktop GUI:** Run `sudo bash create-autoinstall-usb.sh --gui` (opens native GTK `zenity` dialogs, or falls back to the `whiptail` TUI).
   - **Ubuntu Terminal TUI:** Run `sudo bash create-autoinstall-usb.sh` (or `--tui`).
   - **Ubuntu Scripted CLI:** Run `sudo bash create-autoinstall-usb.sh --iso ... --offline-bundle ... --device /dev/sdX --hostname oscar-host --username oscaradmin --password-file ... --require-sudo-password --oscar-admin-password-file ... --lanes-file lanes.csv --auto-init-oscar --confirm ERASE-USB`.

### Turnkey Fresh-Site Pre-Configuration (Zero Plaintext Secrets on USB)

When building the USB stick, you can optionally supply:
- **Initial OSCAR Web `admin` Password (14+ chars):** Immediately salted and PBKDF2-hashed in memory (`# PBKDF2_PREENCODED:PBKDF2WithHmacSHA1:16:...`) before writing to `OSCAR_MEDIA/seed/oscar-admin-password.txt`—neither the Linux `oscaradmin` password nor the OSCAR web `admin` password is ever stored in plaintext on the USB stick, and the seed hash is automatically deleted after first-boot initialization.
- **Pre-Configured Site Lanes (`lanes.csv` or `config.json`):** Stages your lane spreadsheet or SensorHub configuration directly into `OSCAR_MEDIA/seed/`.
- **Auto-Initialize OSCAR on First Boot (`-AutoInitOscar` / `--auto-init-oscar`):** Automatically runs `prepare-host`, `oscar init`, lane/config import, and HTTPS verification unattended on first boot (`oscar-autoprovision.service`), so on arrival at the site you only open `https://<hostname>/`, sign in as `admin`, register site operators, and upload `.pmtiles` or the site background diagram.
- **Printable Technician Handover One-Sheet PDF (`--one-sheet-pdf` / `-OneSheetPdfPath`):** Automatically generates a clean, single-page US Letter PDF strictly on the staging workstation (owner-only permissions: `0600` on Linux, restricted current-user NTFS ACL on Windows; **never** written to the USB drive) listing the target hostname, URLs, Linux admin username/password, sudo policy, LUKS2 disk-encryption passphrase, SSH key policy, initial OSCAR web `admin` password, staged backup key & static network summary (`site-network.env`), verified bundle SHA-256 checksum, staged seed files, post-autoinstall field checklist, and a sign-off block. Print it for the site security binder and securely delete the digital copy after handover (or pass `--no-one-sheet-pdf` / `-NoOneSheetPdf` to skip).

## Contents

| File | When to Use |
| --- | --- |
| `create-autoinstall-usb.bat`, `create-autoinstall-usb.ps1` & `create-autoinstall-usb.sh` | Cross-platform bare-metal Ubuntu 24.04 autoinstall USB creator (**GUI + TUI + CLI**) for **Windows 11** (`create-autoinstall-usb.bat` / `.\oscar.bat create-autoinstall-usb`) and **Ubuntu** (`sudo bash create-autoinstall-usb.sh` / `sudo bash oscar.sh create-autoinstall-usb`). Writes the signed Ubuntu 24.04 Live Server ISO, `CIDATA` cloud-init profile (custom hostname, admin username, native `$6$` SHA-512 password hash, optional LUKS2 full-disk encryption, `--require-sudo-password`, and `--ssh-keys-only` SSH hardening), `OSCAR_MEDIA` offline bundle with verified SHA-256, and optional `seed/` imports onto a single external USB drive while strictly protecting internal OS and `OSCAR_BACKUP` disks. |
| `oscar-firstboot-wizard.sh` | Interactive post-autoinstall provisioning & recovery TUI (`sudo bash oscar.sh wizard` / `sudo oscar-wizard`, auto-launched on first login): optimizes the Ubuntu host offline, mounts attached USB drives read-only (`-o ro`), and lets the administrator choose USB NVMe Backup Restore, Single-Snapshot Restore, Fresh Install + `config.json` / `lanes.csv` / `.pmtiles` Import, or Clean Site Init. |
| `site-network.example.env` | Simple fill-in-the-blanks worksheet for staging site static IPs in a hotel room (`sudo bash oscar.sh stage-site-network --config ubuntu/site-network.env`) without dropping hotel Wi-Fi/DHCP. |
| `netplan/01-single-nic-static.yaml.example` | Netplan v2 template when Operator PCs, RPMs, and cameras share a single Ethernet switch (with or without a default gateway). |
| `netplan/02-dual-nic-operator-and-sensor-vlan.yaml.example` | Netplan v2 template for 2-NIC portal servers: Port 1 = Operator/Site LAN, Port 2 = Isolated air-gapped RPM & camera switch (`optional: true`, no gateway). |
| `autoinstall/user-data.yaml` & `autoinstall/meta-data` | Zero-touch declarative Ubuntu Server 24.04 `cloud-init` installer config (`CIDATA` USB label or PXE): allocates `100%` of the NVMe (`sizing-policy: all`), skips Snap Docker, enables SSH, and prevents offline boot hangs. |
| `ansible-site-hosts.yml` | Optional single-file Ansible playbook to converge one or multiple Ubuntu 24.04 hosts remotely over SSH from a laptop. |
