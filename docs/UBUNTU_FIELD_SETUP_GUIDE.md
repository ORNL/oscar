# Ubuntu 24.04 Field Setup, Hotel-Room Staging & Air-Gapped Bare-Metal Guide

This guide walks step-by-step through setting up an Ubuntu 24.04 LTS server for **OSCAR 3.11.13** from scratch — **even if you have never used Ubuntu Linux or OSCAR before**.

It covers all three real-world field deployment scenarios:

- **[Scenario A — Hotel-Room / Off-Site Pre-Staging](#4-scenario-a--hotel-room--off-site-staging-dhcpwi-fi-now--static-ip-on-site-later):** You have hotel Wi-Fi or Ethernet (dynamic DHCP) and the site schematic. You install Ubuntu, Docker, OSCAR, users, and lane IPs in the hotel room, pre-stage the site's static IPs **without losing hotel internet**, and then run **one command** (`sudo bash oscar.sh apply-site-network`) when you plug into the switches on-site (even if the site is completely offline with no DHCP).
- **[Scenario B — 100% Bare-Metal Air-Gapped On-Site Setup](#5-scenario-b--bare-metal-from-scratch-on-site-with-zero-internet--zero-dhcp):** You arrive at an offline facility with a blank computer, no internet, and no DHCP, and install Ubuntu 24.04 + Docker + OSCAR completely offline from a USB drive.
- **[Scenario C — Discovering Unknown RPM & Camera IPs On-Site](#6-scenario-c--when-rpm-or-camera-ip-addresses-are-unknown-on-site):** You arrive on-site without a complete IP sheet (or cameras/RPMs are sitting on unknown/factory subnets with no DHCP) and use `sudo bash oscar.sh discover-devices` to find every live camera and RPM controller on the wire.

> **Captioned Video Walkthrough (`#26`, `15.6s`):** Watch **[Stage Ubuntu 24.04 Off-Site & Cut Over to Air-Gapped Portal Subnets](VIDEO_GUIDES.md#26-ubuntu-hotel-staging-and-airgapped-cutover)** ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/26-ubuntu-hotel-staging-and-airgapped-cutover.mp4) · [WebVTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/26-ubuntu-hotel-staging-and-airgapped-cutover.vtt), also bundled offline inside OSCAR at `/video-guides/index.html` and **Help (`?`)**).

---

## 1. Pre-Trip USB Kit & Direct Official Download Links

Before traveling to a hotel or air-gapped site, prepare a compact **two-drive field kit**:
1. **One `32 GB+` USB 3.0 flash drive** for the **OSCAR Bare-Metal Ubuntu 24.04 Autoinstall USB** (or **Ventoy** multi-ISO installer stick holding the Ubuntu `.iso`, OSCAR `.zip`, and pre-staged `lanes.csv`).
2. **One rugged `1–2 TB` External USB 3.2 Gen 2 NVMe SSD** (for example, Samsung T7 Shield or Crucial X9/X10 Pro) dedicated to **`OSCAR_BACKUP` (`continual` 15-minute incremental backup)**—leave this NVMe SSD plugged into the server on-site for hardware-isolated disaster recovery, **`0.0 s`-downtime `~5–20 s` pre-upgrade syncs** during future system updates, and 1-command bare-metal replacement (or bring an existing site's `OSCAR_BACKUP` NVMe SSD when restoring onto new hardware).

### 1.1 Official Operating System & Bootable USB Tool Links

| Tool / Media | Official Download URL | Which File to Pick & Why |
| --- | --- | --- |
| **Ubuntu Server 24.04 LTS ISO** *(Recommended for 24/7 portals)* | [https://releases.ubuntu.com/24.04/](https://releases.ubuntu.com/24.04/) | Download **`ubuntu-24.04.2-live-server-amd64.iso`** (or latest `24.04.x-live-server-amd64.iso`, ~`2.6 GB`). Lowest memory/CPU overhead for 24/7 portals. |
| **Ubuntu Desktop 24.04 LTS ISO** *(Optional if you want a local monitor/mouse browser on the server itself)* | [https://releases.ubuntu.com/24.04/](https://releases.ubuntu.com/24.04/) | Download **`ubuntu-24.04.2-desktop-amd64.iso`** (~`5.8 GB`). OSCAR's Ubuntu scripts automatically detect Desktop (`NetworkManager`) vs. Server (`networkd`). |
| **Ventoy Multi-File Bootable USB Creator** *(Strongly Recommended)* | [https://www.ventoy.net/en/download.html](https://www.ventoy.net/en/download.html) | Install Ventoy once onto a 32 GB+ USB stick, then **drag-and-drop** the Ubuntu `.iso` *plus* the OSCAR `.zip` *plus* your `site-network.env` file straight onto the same USB stick like a normal folder! |
| **Rufus** *(Alternative single-ISO USB flasher for Windows)* | [https://rufus.ie/](https://rufus.ie/) | Download `rufus-<version>p.exe` (Portable). Writes one `.iso` to one USB stick; put the OSCAR `.zip` on a second USB stick. |
| **balenaEtcher** *(Alternative USB flasher for macOS / Windows)* | [https://etcher.balena.io/](https://etcher.balena.io/) | Simple 3-click `.iso` USB writer (use a second USB stick for the OSCAR `.zip`). |

### 1.2 Which OSCAR 3.11.13 Release File Should You Put on the USB Stick?

Download from **[GitHub Releases — `ORNL/oscar` `v3.11.13`](https://github.com/ORNL/oscar/releases/tag/v3.11.13)**:

| OSCAR Release Asset | Size | When to Use |
| --- | --- | --- |
| **`oscar-3.11.13-autoinstall-usb-creator.zip`** *(Standalone USB Builder — GUI + TUI + CLI)* | `~53 KB` | **Builds a zero-touch Ubuntu 24.04 + OSCAR Autoinstall USB directly on Windows 11 (`create-autoinstall-usb.bat` GUI/TUI/CLI) or Ubuntu (`create-autoinstall-usb.sh` GUI/TUI/CLI)** using `ubuntu-24.04.x-live-server-amd64.iso` and `oscar-3.11.13-ubuntu-x86_64-offline-full.zip` without unpacking the offline bundle first—including optional PBKDF2-hashed initial OSCAR web `admin` password, `lanes.csv` / `config.json` lane pre-configuration, and unattended first-boot OSCAR initialization. |
| **`oscar-3.11.13-ubuntu-x86_64-offline-full.zip`** *(Best all-around field choice)* | `~1.1 GB` | **Works BOTH completely offline on-site AND in a hotel room.** Includes OSCAR 3.11.13, pre-built `oscar`, `oscar-postgis`, and `nginx` Docker images (`offline-images.tar`), *plus* official Ubuntu 24.04 `.deb` installers for Docker Engine, Compose v2, `chrony`, `ethtool`, `nmap`, and `arp-scan`. **Zero hotel Wi-Fi downloads needed!** |
| **`oscar-3.11.13.zip`** *(Connected release)* | `~611 MB` | Smaller download when you know you will run `prepare-host` and `init` over fast internet (for example, in the office or hotel room). |

Also download **`OSCAR-3.11.13-Administrator-Operator-Manual-en.pdf`** and **`OSCAR-3.11.13-SHA256SUMS.txt`** onto the USB stick so you have offline manuals and checksum verification on-site.

> **Captioned Video Walkthrough (`#31`, `67s`):** Watch **[Build an Air-Gapped Ubuntu 24.04 Autoinstall USB Drive (GUI, TUI & CLI)](VIDEO_GUIDES.md#31-bare-metal-autoinstall-usb-creator)** ([MP4](https://github.com/ORNL/oscar-video-guides/blob/main/videos/31-bare-metal-autoinstall-usb-creator.mp4) · [WebVTT](https://github.com/ORNL/oscar-video-guides/blob/main/captions/31-bare-metal-autoinstall-usb-creator.vtt)).

![Bare-Metal Ubuntu 24.04 Offline Autoinstall USB Creator GUI](https://raw.githubusercontent.com/ORNL/osh-oakridge-modules/main/docs/oscar-operator-manual/images/55-bare-metal-autoinstall-usb-creator.png)

### 1.3 Helpful Laptop Apps (If Administering From Your Windows/Mac Laptop)

- **SSH & Terminal:** Built into Windows 11 (**Windows Terminal** / PowerShell: `ssh oscaradmin@<IP>`) and macOS (**Terminal**).
- **Drag-and-Drop File Transfer over SSH:** **[WinSCP](https://winscp.net/eng/download.php)** (Windows) or **[Cyberduck](https://cyberduck.io/download/)** (Windows/macOS) — lets you copy Lane CSVs, TLS certificates, or backups to/from the Ubuntu server visually without typing `scp` commands.

---

## 2. Two-Minute Ubuntu Survival Cheat Sheet (For First-Time Linux Users)

If you have never touched an Ubuntu terminal before, these **7 commands** are all you need:

| What You Want to Do | Exact Command to Type |
| --- | --- |
| Run an administrator command (`sudo` prompts once for your Ubuntu login password; **characters do not show as stars while typing** — just type the password and press `Enter`) | `sudo bash oscar.sh status` |
| Open OSCAR's interactive text menu so you don't have to remember flags | `sudo bash oscar.sh` |
| Edit a simple text/config file (`Ctrl+O` then `Enter` saves; `Ctrl+X` exits) | `nano site-network.env` |
| See all physical network ports, MAC addresses, and which cables are plugged in | `sudo bash oscar.sh identify-nics` |
| Watch live as you plug/unplug Ethernet cables to label Port 1 vs. Port 2 | `sudo bash oscar.sh identify-nics --watch` |
| Mount and copy files from a USB thumb drive on Ubuntu Server (no desktop) | See [Section 5.2](#52-copy-the-oscar-offline-bundle-off-your-usb-stick) below (4 copy-paste lines) |
| Safely shut down the server before unplugging power in the hotel room | `sudo poweroff` |

---

## 3. Installing Ubuntu 24.04 LTS on Bare Metal (Avoiding the Two Classic Traps)

You can install Ubuntu Server 24.04 either **interactively** (5 minutes with keyboard & monitor) or **declaratively/automatically** using OSCAR's included [`user-data.yaml`](../dist/release/ubuntu/autoinstall/user-data.yaml).

> **CRITICAL — Avoid These Two Ubuntu Installer Traps:**
> 1. **Trap #1 (The `100 GiB` Disk Cap):** On the *Guided storage configuration* screen, Ubuntu Server defaults to allocating **only `100 GB`** to `ubuntu-lv` even if your NVMe SSD is `2 TB` or `4 TB`! Either change the `ubuntu-lv` size to the maximum available value during install, **or** pass `--expand-lvm` when you run `sudo bash oscar.sh prepare-host --expand-lvm` afterward (OSCAR will reclaim 100% of the disk automatically!).
> 2. **Trap #2 (The `docker` Snap Checkbox):** Near the end of the Ubuntu Server installer, a screen titled **Featured Server Snaps** shows a list with `[ ] docker`. **DO NOT CHECK `docker`!** Leave **all** server snaps unchecked. Snap-confined Docker breaks storage bind mounts and restarts containers unexpectedly. OSCAR's `prepare-host` installs the official Docker Engine (`docker-ce`) cleanly instead.

### Option 3A — Interactive Bare-Metal Install (Recommended First Time)

1. Plug your Ventoy/Rufus USB stick, monitor, and keyboard into the server, power on, and press the boot-menu key (`F12` on Dell/Lenovo, `F11` on Supermicro/ASRock, `F7` on Intel/ASUS NUC, `F9` on HP).
2. Select your **UEFI USB drive** -> **Boot in normal mode** -> **Try or Install Ubuntu Server**.
3. Step through the screens:
   - **Language / Keyboard:** `English` / `US`.
   - **Install type:** `Ubuntu Server` (default).
   - **Network connections:**
     - *In a hotel room:* Plug in hotel Ethernet (or select your Wi-Fi adapter -> enter hotel Wi-Fi credentials if simple WPA2; if hotel Wi-Fi has a browser captive portal, either install **Ubuntu Desktop 24.04**, tether your phone via USB cable, or use **`oscar-3.11.13-ubuntu-x86_64-offline-full.zip`** so zero internet is needed!).
     - *On an offline site with no DHCP:* Select **Continue without network** — you do **not** need network during Ubuntu installation!
   - **Proxy / Mirror:** Leave blank / default (`Done`).
   - **Guided storage configuration:** Keep `[X] Use an entire disk` and `[X] Set up this disk as an LVM group` -> press `Done`. On the **Storage configuration summary** page, if `ubuntu-lv` says `100.000G` on a larger SSD, select `ubuntu-lv` -> **Edit** -> type the full free size shown (or simply let `sudo bash oscar.sh prepare-host --expand-lvm` expand it later) -> `Done` -> `Continue`.
   - **Profile setup:**
     - Your name: `OSCAR Admin`
     - Your server's name: `oscar-host`
     - Pick a username: `oscaradmin`
     - Choose a strong password (write it down with your site packet).
   - **Ubuntu Pro:** Skip (`Continue`).
   - **SSH Setup:** Press `Space` to check **`[X] Install OpenSSH server`** -> `Done`.
   - **Featured Server Snaps:** **Leave EVERYTHING UNCHECKED (especially do NOT check `docker`)!** -> `Done`.
4. Wait ~3 minutes for installation to finish -> select **Reboot Now** -> remove the USB stick when prompted and press `Enter`.

### Option 3B — Declarative Zero-Touch Bare-Metal Install + First-Boot Wizard (`create-autoinstall-usb` + `oscar-wizard`)

If you want a **single-stick unattended bare-metal installer** that installs Ubuntu Server 24.04 LTS onto the target server's internal NVMe/SSD (`100%` LVM capacity, never touching USB drives), configures USB-to-NVMe Bulk-Only Transport + No-LPM stability quirks from first boot, unpacks `oscar-3.11.13-ubuntu-x86_64-offline-full.zip` into `/srv/oscar/`, and launches an interactive menu on first login:

1. **Build the Bare-Metal Autoinstall USB Stick** on either **Windows 11** or **Ubuntu**:
   - **On Windows 11 (Administrator prompt, zero third-party tools needed):**
     ```powershell
     .\oscar.bat create-autoinstall-usb
     ```
   - **On Ubuntu Linux:**
     ```bash
     sudo bash oscar.sh create-autoinstall-usb
     ```
   Select your removable external USB drive (`16 GB+`), point to `ubuntu-24.04.x-live-server-amd64.iso` and `oscar-3.11.13-ubuntu-x86_64-offline-full.zip`, set a strong custom Linux password for `oscaradmin`, and optionally pre-configure the **initial OSCAR web `admin` password** (`14+` chars, hashed in memory via PBKDF2 so zero plaintext ever touches the USB stick), **`lanes.csv` or `config.json`**, and **Auto-initialize OSCAR on first boot** (`-AutoInitOscar` / `--auto-init-oscar`)—so on arrival at the site you only open `https://<hostname>/`, register site users, and upload `.pmtiles` or the site diagram! You can also supply an extra `seed/` folder containing `site-network.env`, `*.pmtiles`, or `backup-key.txt`.
   - **Production Bare-Metal Security Hardening (Strongly Recommended):** Because host `sudo` / physical disk access governs break-glass recovery (`sudo bash oscar.sh reset-admin-password`) and persistent volumes, lock down bare-metal autoinstall deployments from minute zero by passing **`--luks-passphrase-file FILE`** (`-LuksPassphraseFile FILE` on Windows) for **LUKS2 Full-Disk Encryption** across 100% of the internal NVMe (optionally enrolling hands-free TPM 2.0 `PCR 0+7` boot unlock afterward via `sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/nvme0n1p3`), **`--require-sudo-password`** (`-RequireSudoPassword`) so `sudo` always requires OS password re-entry (never `NOPASSWD:ALL`), and **`--ssh-key-file ~/.ssh/id_ed25519.pub --ssh-keys-only`** (`-SshKeyFile ... -SshKeysOnly`) to disable SSH password and root logins. After commissioning, lock UEFI Setup with a supervisor password, keep Secure Boot enabled, disable external USB boot priority, store or erase the `CIDATA` installer stick, optionally restrict `22/tcp` via `sudo bash oscar.sh prepare-host --ufw-ssh-cidr <MGMT_CIDR>` (or `--ufw-disable-ssh` on local-console-only portals), never add operator accounts to the Linux OS or `docker` group, and verify with `sudo bash oscar.sh host-check --strict`.
2. **Boot the Target Server Offline:** Insert the USB drive, choose it from the UEFI One-Time Boot Menu (`F9`/`F11`/`F12`), and wait ~4 minutes while Ubuntu 24.04 + `/srv/oscar/` install with zero prompts. Remove the installer USB when prompted and press `Enter`.
3. **Interactive First-Boot Provisioning & Recovery Wizard (`sudo oscar-wizard`):** On your first login as `oscaradmin` (or anytime via `sudo oscar-wizard` / `sudo bash oscar.sh wizard`), OSCAR mutes kernel console `printk` noise so `tty1` dialogs stay crisp, runs offline host optimization (Docker Engine, sysctl, UFW, LVM, and USB-NVMe quirks), scans attached USB drives read-only (`-o ro` — zero manual `mount`/`cp`/`umount` commands, automatically skipping EFI `ESP` boot partitions and cleaning up unplugged sticks on `RESCAN`), and lets you pick:
   - **Restore from Continual / Occasional USB NVMe Backup** (`usb-backup restore`, including an interactive **Safe Bench / DR Clone Isolation** option that blocks outbound sensor/tunnel traffic via `DOCKER-USER` when testing a backup on the same network as an active portal)
   - **Restore from Single-Snapshot Backup** (`oscar restore`, with optional `--bench-isolation`)
   - **Fresh Install + Import Configuration** (`config.json` lanes/sensors, `lanes.csv` spreadsheet, and/or `.pmtiles` offline basemap)
   - **Clean Fresh Site Installation** (`oscar init`, with optional hotel/site static IP setup)

> **Hardware Power Tip When Restoring from `1–4 TB` M.2 NVMe USB Enclosures on Laptops:** High-capacity M.2 PCIe NVMe SSDs in USB 3.2 bridge enclosures draw **`6–8 W` (`1.1–1.6 A`)** at spin-up. Standard laptop USB-A ports (`4.5 W`) or shared dual Thunderbolt/USB-C ports that already have a USB-C Ethernet dongle plugged in first can brown out the drive (`state=not attached` / enclosure LED off). Connect `1–4 TB` NVMe backup enclosures through a **mains-powered USB 3.2 Gen 2 hub/dock** (or plug the NVMe enclosure into a dedicated `15 W` USB-C port *before* plugging in low-power USB Ethernet adapters).

---

## 4. Scenario A — Hotel-Room / Off-Site Staging (DHCP/Wi-Fi Now → Static IP On-Site Later)

This is the recommended workflow whenever you receive the server hardware and the **site network schematic** before arriving at the portal.

### Step A1 — Connect to Hotel Internet & Extract OSCAR

Log into Ubuntu (`oscaradmin`) and create the `/srv/oscar` directory:

```bash
sudo mkdir -p /srv/oscar
sudo chown "$USER:$USER" /srv/oscar
cd /srv/oscar
```

Copy `oscar-3.11.13-ubuntu-x86_64-offline-full.zip` (or `oscar-3.11.13.zip` if downloading over hotel Wi-Fi) into `/srv/oscar` and extract it:

```bash
unzip oscar-3.11.13-ubuntu-x86_64-offline-full.zip
cd oscar-3.11.13-ubuntu-x86_64-offline-full
# (Or if using the connected zip: unzip oscar-3.11.13.zip && cd oscar-3.11.13)
```

### Step A2 — Run `prepare-host` (Installs Docker, Expands Disk, Disables Sleep & 2 AM Reboots)

```bash
sudo bash oscar.sh prepare-host --expand-lvm --configure-ufw
```

What this single command configures automatically:
- Installs official **Docker Engine + Docker Compose v2** (`docker-ce`, using bundled `.deb`s automatically if you extracted `offline-full`, or official APT over hotel internet if you extracted `oscar-3.11.13.zip`).
- Expands Ubuntu's `100 GiB` LVM root volume (`--expand-lvm`) so 100% of your NVMe SSD is available.
- Configures `/etc/docker/daemon.json` log rotation (`50m` × `5`), masks `sleep`/`suspend`/`hibernate`/lid-close, disables `unattended-upgrades` automatic reboots, tunes RTSP/PostgreSQL kernel socket buffers (`/etc/sysctl.d/90-oscar.conf`), bounds boot network wait to `10s` so offline sites never stall at boot, configures `chrony` offline clock stability, and opens `22/tcp`, `80/tcp`, and `443/tcp` in `ufw`.

### Step A3 — Physically Identify & Label the Server's Ethernet Ports (`identify-nics`)

Mini-PCs and 1U servers often have 2 or 4 RJ45 ports whose Linux names (`enp1s0`, `enp2s0`, `eno1`, `eno2`) do not match the numbers printed on the chassis. Run:

```bash
sudo bash oscar.sh identify-nics --watch
```

Plug a short patch cable (or your laptop's Ethernet port) into **Port 1**, watch the terminal print `>>> enp1s0 changed to PLUGGED_IN <<<`, and put a piece of label tape on that physical jack (`enp1s0 — SITE LAN`). Repeat for **Port 2** (`enp2s0 — SENSORS`), then press `Ctrl+C`.

### Step A4 — Pre-Stage the Site Static IPs *Without* Losing Hotel Internet (`stage-site-network`)

Run the interactive staging wizard:

```bash
sudo bash oscar.sh stage-site-network
```

*(Or fill out `cp ubuntu/site-network.example.env site-network.env && nano site-network.env` from your site schematic and run `sudo bash oscar.sh stage-site-network --config site-network.env`.)*

- Enter your on-site **Primary / Operator LAN port** (e.g. `enp1s0`), **Static IP** (accepts either `198.51.100.10/24` *or* `198.51.100.10` + subnet mask `255.255.255.0`), and **Gateway / DNS** (press `Enter` to leave blank if the site is an isolated offline switch with no router!).
- If your server has a **2nd Ethernet port for RPMs & Cameras**, answer `y` and enter e.g. `enp2s0` and `203.0.113.10/24` (OSCAR automatically sets `optional: true` and **omits** any gateway on the sensor port so sensor traffic never hijacks default routing).
- **Your hotel Wi-Fi / DHCP stays 100% connected!** OSCAR validates the YAML with `netplan generate` and stages it safely in `/etc/oscar/staged-netplan/90-oscar-site.yaml` for on-site activation.

### Step A5 — Initialize OSCAR & Pre-Configure Lanes and Users in the Hotel Room

Now run `init`:

```bash
sudo bash oscar.sh init
```

- Because you ran `stage-site-network` first, `oscar.sh init` **automatically embeds BOTH your current hotel IP and your staged future on-site static IPs** into `tls/server.crt`!
- Open `https://<HOTEL_OR_LOCALHOST_IP>/` in your browser, sign in with your administrator password, and complete all configuration in the comfort of the hotel room:
  1. **Users & Access (`/users`):** Create operator accounts or run **Bulk Enroll (CSV)**.
  2. **SensorHub Admin (`/sensorhub/admin`) / Lane CSV Import:** Add all RPM lanes and RTSP camera IPs from your site schematic. *(It is completely normal for lanes to show disconnected/red while in the hotel room — OSCAR persists every lane driver and automatically connects as soon as the physical sensors are reachable on-site!)*
- Verify everything is saved (`sudo bash oscar.sh status`), then power down cleanly for transport to the site:

```bash
sudo poweroff
```

### Step A6 — On-Site Arrival Cutover (Takes Under 60 Seconds, Zero Internet Needed!)

When you arrive at the site:
1. Rack/place the server, plug the site Ethernet cables into your labeled ports (`SITE LAN` and `SENSORS`), and power on the machine.
   - Because `docker.service` is enabled and OSCAR uses `restart: unless-stopped`, **OSCAR starts automatically on power-up**!
2. Log in at the server keyboard/monitor (or via hotel/laptop link) and activate your staged static IP plan with **one command**:

```bash
cd /srv/oscar/oscar-3.11.13-ubuntu-x86_64-offline-full   # (or /srv/oscar/oscar-3.11.13)
sudo bash oscar.sh apply-site-network
```

`apply-site-network` automatically:
1. Backs up your previous DHCP Netplan files to `/etc/oscar/netplan-backups/<timestamp>/` (so `sudo bash oscar.sh rollback-network` can undo it in 2 seconds if needed),
2. Switches the NICs from dynamic DHCP to your exact static site IPs (`dhcp4: false`, `optional: true` — works on 100% offline switches with **no DHCP and no router**),
3. Prints live `PLUGGED_IN` / `unplugged` cable verification so you immediately see if a patch cord is loose,
4. Refreshes `tls/server.crt` SANs (`refresh-tls`) if any IP changed and verifies `gateway`, `oscar`, and `postgres` are all **`Up (healthy)`**!

---

## 5. Scenario B — Bare-Metal From Scratch On-Site With Zero Internet & Zero DHCP

When you must build a blank machine inside an air-gapped facility with **no internet and no DHCP**:

### 5.1 Install Ubuntu 24.04 Offline From Your USB Drive

Follow **[Option 3A](#option-3a--interactive-bare-metal-install-recommended-first-time)** above:
- On the **Network connections** installer screen, select **Continue without network** (do not wait for DHCP).
- Remember: check **`[X] Install OpenSSH server`** and leave **Featured Server Snaps completely unchecked**.
- Reboot into your fresh Ubuntu system and log in as `oscaradmin`.

### 5.2 Copy the OSCAR Offline Bundle Off Your USB Stick

Plug in the USB stick containing **`oscar-3.11.13-ubuntu-x86_64-offline-full.zip`** and run these 4 commands to mount the USB drive and extract the bundle:

```bash
# 1. List attached disks/USB partitions (look for TYPE="part" on a removable USB drive, e.g. sdb1 or sdc1):
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS

# 2. Mount the USB partition (replace /dev/sdb1 below with your USB partition from lsblk):
sudo mkdir -p /mnt/usb /srv/oscar
sudo mount -o ro /dev/sdb1 /mnt/usb

# 3. Copy and extract the offline bundle onto the server's internal NVMe SSD:
sudo chown "$USER:$USER" /srv/oscar
unzip /mnt/usb/oscar-3.11.13-ubuntu-x86_64-offline-full.zip -d /srv/oscar
sudo umount /mnt/usb

# 4. Enter the extracted release directory and verify every SHA-256 checksum offline:
cd /srv/oscar/oscar-3.11.13-ubuntu-x86_64-offline-full
sudo bash verify-bundle.sh
```

### 5.3 Install Docker & Tune Ubuntu 100% Offline, Configure Static NICs, and Initialize OSCAR

```bash
# 1. Install bundled Docker Engine .debs + chrony + nmap + ethtool + expand 100 GiB LVM (zero internet):
sudo bash oscar.sh prepare-host --offline --expand-lvm --configure-ufw

# 2. Identify physical NIC ports by plugging in cables one at a time:
sudo bash oscar.sh identify-nics --watch

# 3. Configure and activate your on-site static IPv4 addresses (no DHCP required):
sudo bash oscar.sh stage-site-network
sudo bash oscar.sh apply-site-network

# 4. Initialize OSCAR from the bundled offline-images.tar (zero internet):
sudo bash oscar.sh init
```

OSCAR loads `oscar:3.11.13`, `oscar-postgis:3.11.13`, and `nginx/nginx-unprivileged:1.30.7-alpine` directly from `offline-images.tar`, generates your TLS certificate covering the static NIC IPs, initializes PostgreSQL with `data_checksums=on`, and starts all services cleanly offline.

---

## 6. Scenario C — When RPM or Camera IP Addresses Are Unknown On-Site

Sometimes you arrive on-site and the camera installer or site electrician did not leave an IP sheet — or cameras/RPMs are sitting on an isolated PoE switch with **no DHCP server**.

### 6.1 Scan the Attached Sensor Subnet (`discover-devices`)

If your sensor NIC (`enp2s0`) already has its static IP (for example `203.0.113.10/24`), scan that wire directly:

```bash
sudo bash oscar.sh discover-devices --interface enp2s0
```

OSCAR scans the subnet via ARP + TCP port probes and prints a table classifying every live device (and saves `/tmp/oscar-discovered-devices.csv`):
- **`554` / `8554` open:** `Likely IP Camera (RTSP)`
- **`10001` / `2101` / `4001` / `4002` / `502` open:** `Likely RPM / Serial-Ethernet Controller` (Moxa NPort, Lantronix, Rapiscan, Aspect)
- **`80` / `443` / `8000` / `8080` open:** `Web-Managed Device / Camera / Switch`

### 6.2 Probe Common Factory-Default Subnets on a No-DHCP Switch (`--temp-ip`)

If `discover-devices` finds `0` devices on your planned subnet, unconfigured cameras or serial adapters may still be sitting on their **factory-default static subnet** (commonly `192.168.1.0/24` for Hikvision/Dahua, `192.168.0.0/24` for Axis/D-Link, `192.168.127.0/24` for Moxa NPort, or `10.0.0.0/24`).

Use `--temp-ip` to temporarily attach a non-disruptive probe address during the scan (OSCAR automatically removes the temporary IP as soon as the scan finishes!):

```bash
sudo bash oscar.sh discover-devices --interface enp2s0 --temp-ip 192.168.1.250/24
sudo bash oscar.sh discover-devices --interface enp2s0 --temp-ip 192.168.0.250/24
sudo bash oscar.sh discover-devices --interface enp2s0 --temp-ip 192.168.127.250/24
```

### 6.3 Verify a Discovered RTSP Stream Before Adding to a Lane

Once you find a camera IP (e.g. `203.0.113.51`), you can test its RTSP URL right from the Ubuntu server using `ffprobe` inside the running `oscar` container:

```bash
sudo docker exec oscar-oscar-1 ffprobe -v error -rtsp_transport tcp \
  -show_entries stream=codec_name,width,height,r_frame_rate \
  -of default=noprint_wrappers=1 \
  "rtsp://USER:PASSWORD@203.0.113.51:554/Streaming/Channels/101"
```

Confirm the output shows `codec_name=h264` (recommended `1280x720` or `1920x1080` @ `15/1` fps), then enter that IP/URL in **SensorHub Admin (`/sensorhub/admin`)** and click **Save Configuration**!

---

## 7. Declarative Templates & Emergency Recovery Reference

All declarative templates are packaged in [`ubuntu/`](../dist/release/ubuntu/README.md) inside every release archive:

| Template / Command | Purpose |
| --- | --- |
| [`ubuntu/site-network.example.env`](../dist/release/ubuntu/site-network.example.env) | Simple `KEY=VALUE` worksheet for `sudo bash oscar.sh stage-site-network --config site-network.env`. |
| [`ubuntu/netplan/01-single-nic-static.yaml.example`](../dist/release/ubuntu/netplan/01-single-nic-static.yaml.example) | Single-NIC static IPv4 Netplan v2 YAML (`optional: true`). |
| [`ubuntu/netplan/02-dual-nic-operator-and-sensor-vlan.yaml.example`](../dist/release/ubuntu/netplan/02-dual-nic-operator-and-sensor-vlan.yaml.example) | Dual-NIC Operator LAN + Isolated Sensor VLAN Netplan v2 YAML (no gateway on sensor NIC). |
| [`ubuntu/autoinstall/user-data.yaml`](../dist/release/ubuntu/autoinstall/user-data.yaml) | Bare-metal zero-touch Ubuntu Server 24.04 `cloud-init` installer config (`CIDATA`). |
| [`ubuntu/ansible-site-hosts.yml`](../dist/release/ubuntu/ansible-site-hosts.yml) | Single-file Ansible playbook for remote multi-host hotel/site staging over SSH. |
| `sudo bash oscar.sh host-check` | Runs 12 automated readiness checks (`--json` and `--strict` supported). |
| `sudo bash oscar.sh refresh-tls --tls-san <NEW_IP>` | Re-issues `tls/server.crt` + reloads `gateway` in 3 seconds if the site changes your server IP after arrival. |
| `sudo bash oscar.sh rollback-network` | Immediately restores your pre-cutover DHCP `/etc/netplan` backup if a static IP had a typo. |
| `sudo bash oscar.sh support-bundle` | Exports a redacted `.zip` diagnostic bundle from the terminal even if the browser UI is unreachable. |
