# OSCAR 3.11.0 Continual & Occasional USB NVMe Incremental Backup Guide

OSCAR 3.11.0 provides a zero-downtime, incremental **USB NVMe Backup & Field Offload** workflow (`usb-backup` / `continual-backup`) designed specifically for **multi-year (`1–10` year, `40–900+ GiB`) deployments**, external **USB 3.2 Gen 2 NVMe SSDs**, **seamless mode switching** between continual and occasional schedules, **laptop-based field data offloads**, and **fast bare-metal server migration** across Ubuntu Server 24.04 LTS and Windows 11.

For the single-snapshot quiesced recovery workflow (`OSCAR_BACKUP_MODE=single` via `oscar backup`), see [Backup, Restore, and Recovery](BACKUP_RESTORE.md) and [Administrator Guide](../dist/release/DEPLOYMENT.md).

---

## 1. Which Backup Workflow Should You Use?

| Capability | `usb-backup mode continual` *(Recommended for 1–10 Year Portals)* | `usb-backup mode occasional` *(On-Demand Incremental)* | Legacy `oscar backup` (`OSCAR_BACKUP_MODE=single`) |
| :--- | :--- | :--- | :--- |
| **Portal Downtime During Backup** | **`0.0 seconds`** (online streamed `pg_basebackup` + read-only volume delta packs) | **`0.0 seconds`** (optional `--quiesce` for brief `~15 s` final cutover) | Quiesces `gateway` + `oscar` across full archive packing & verification |
| **5-Year / 50-Lane (`~400 GiB`) Sync Time** | **`~10–30 seconds` per 15-min delta** (prior UTC days are packed once & skipped in `O(1)`) | **`~15–60 seconds`** for new days since last plug-in | `~1.5–3+ hours` (rewrites monolithic `.tar.gz` archives every run) |
| **Peak Backup Drive Space Needed** | **`~1.03×` dataset size** (`~415 GiB` for a `400 GiB` portal; fits a `1–2 TB` USB NVMe SSD) | **`~1.03×` dataset size** | `~2.5–3×` dataset size (`~1.0–1.3 TiB`) |
| **Switch Modes Anytime?** | **Yes** — 1 command switches `continual` ↔ `occasional` ↔ `disabled` | **Yes** — 1 command switches `occasional` ↔ `continual` ↔ `disabled` | Coexists safely (shares the deployment storage lock & `secrets/backup-key.txt`) |
| **Field Laptop Copy (`Win` / `macOS` / `Linux`)** | **Yes** — defaults to `NTFS` with sequential daily `.tar` packs + built-in `COPY-TO-ANOTHER-DRIVE.bat` & `copy-to-another-drive.sh` | **Yes** — identical carrier layout | Manual directory copy of monolithic `.tar.gz` files |
| **Unplug & Auto-Catch-Up Behavior** | Safe 1-command `eject`; while unplugged OSCAR records normally; **plugging back in automatically pulls all missed data** | Plug in anytime, run `usb-backup attach` (or `sync`), then `eject` | Manual invocation only |
| **Cross-Machine & Bare-Metal Restore** | **Yes** — 1-command `usb-backup restore` onto an existing or brand-new uninitialized Ubuntu or Windows server | **Yes** — identical `usb-backup restore` | Requires matching pre-initialized host identity |

---

## 2. Recommended External USB Drive Hardware & Safety Rules

1. **Use an External USB 3.2 Gen 2 (`10 Gbps`) UASP NVMe SSD (`1–2 TB`):**
   - Choose an aluminum/heatsinked or ruggedized portable NVMe SSD (for example, Samsung T7 Shield, Crucial X9/X10 Pro, or an enterprise M.2 TLC NVMe SSD in a UASP enclosure) plugged directly into a **rear motherboard USB 3.x port** (never an unpowered front-panel hub).
   - **Never use USB flash thumb drives, SD cards, or mechanical spinning HDDs:** Thumb drives lack DRAM/wear-leveling and silently corrupt under sustained writes; spinning HDDs stall on metadata seeks and fail under gatehouse vibration.
   - **Never place live OSCAR volumes on USB:** Keep `postgres_data`, `oscar_state`, and live `OSCAR_ARCHIVE_DIR` on internal NVMe; use the external USB NVMe SSD strictly for `usb-backup`.
2. **Keep `NTFS` as the Default Carrier Filesystem for Laptop Portability:**
   - `prepare-drive` formats USB SSDs as **`NTFS`** (`OSCAR_BACKUP` label) by default on **both** Ubuntu Server 24.04 (using Ubuntu's mainline Linux kernel `ntfs3` driver + `ntfs-3g`) and Windows 11.
   - Because `NTFS` mounts natively on **Windows 11**, **macOS** (native Finder read support), and **Linux**, a visiting data administrator can plug the ejected USB SSD into **any** field laptop and copy it onto a second drive at `600–900 MB/s` sequential speed (`--filesystem ext4` is also supported on Ubuntu if only Linux laptops are used).
3. **Store `secrets/backup-key.txt` Separately from the USB SSD:**
   - Every snapshot encrypts `.env`, `secrets/`, `tls/`, and optional Octelium `remote-access/` credentials with **AES-256-CBC (PBKDF2)** and signs `LATEST` + `SHA256SUMS.hmac` with **HMAC-SHA256** using `secrets/backup-key.txt`.
   - Copy `secrets/backup-key.txt` to your organization's password manager or off-site escrow **immediately after running `prepare-drive`**. Never store the only copy of `backup-key.txt` on the same USB SSD.

---

## 2A. Optional Zero-Shell Browser Management (`OSCAR Viewer -> USB Backups`)

Every day-to-day backup and field-visit operation can be managed directly from the browser by any signed-in OSCAR **Administrator** at **`/usb-backups`** (**USB Backups** in the left navigation bar, or from **Users & Access → Recovery → USB NVMe Backups**), localized in **English, Spanish, French, and Greek**—with **zero shell commands required**:

1. **First-Time USB NVMe SSD Initialization:**
   - Plug the external USB 3.x NVMe SSD into the OSCAR host and open **USB Backups** (`/usb-backups`).
   - Under **Initialize or Switch External USB NVMe SSD**, select the detected USB drive (OS boot and active OSCAR disks are hardware-excluded and can never be selected), keep **`NTFS`** selected for universal laptop compatibility, and click **Format & Initialize Selected USB Drive...** (or check **Use existing NTFS/ext4 partition without erasing** to adopt a pre-formatted carrier).
   - Confirm by typing `FORMAT` in the modal dialog; OSCAR partitions/formats the drive, configures boot-safe auto-mounting + USB-NVMe stability rules, writes laptop copy helpers, and streams the initial online snapshot (`0.0 s` portal downtime) with a live progress bar.
   - Click **Download Off-Site Recovery Key (`backup-key.txt`)** and save `oscar-backup-key.txt` in your organization's password manager or off-site vault.
2. **Switching Modes & Schedules Anytime:**
   - Under **Backup Mode & Sync Schedule**, select **Continual Background Sync** (`5`–`1440` minutes, default `15` minutes), **Occasional / On-Demand Visit Sync**, or **Disabled**, and click **Save Mode & Schedule**.
3. **1-Click Visiting Data Admin Offload (`Safely Eject` → Laptop Copy → Re-Plug):**
   - Click **Safely Eject USB Drive** and wait for the green **`SAFE TO UNPLUG`** banner (final delta synced, buffers flushed, and carrier cleanly unmounted while preventing background timers from remounting the drive before you unplug it).
   - Unplug the USB NVMe SSD, run **`COPY-TO-ANOTHER-DRIVE.bat`** (Windows) or **`./copy-to-another-drive.sh`** (macOS/Linux) on your laptop to copy new packs onto a second SSD, then plug the USB NVMe SSD back into the OSCAR USB 3.x port (Ubuntu `continual` mode catches up automatically on hotplug, or click **Re-Attach & Sync Catch-Up** in the panel).

*(Note: Bare-metal disaster recovery onto a brand-new uninitialized replacement server uses the `oscar.sh usb-backup restore` / `oscar.bat usb-backup restore` host command in Section 6 below because OSCAR has not yet been started on the replacement machine.)*

---

## 3. CLI Alternative: Continual vs. Occasional Backup Setup

### Step 1 — Identify Your External USB NVMe SSD

Plug the external USB NVMe SSD into a rear USB 3.x port and list candidate drives (OS/boot and active OSCAR disks are automatically marked protected and can never be formatted):

**Ubuntu Server 24.04:**
```bash
sudo bash oscar.sh usb-backup list-drives
```

**Windows 11 (Administrator PowerShell or `oscar.bat` menu):**
```powershell
.\oscar.bat usb-backup list-drives
```

### Step 2A — Option 1: Set Up **Continual** Automatic USB Backup (Every 15 Minutes, `0s` Downtime)

Formats the USB NVMe SSD as `NTFS`, configures boot-safe mounting (`/etc/fstab` `nofail` on Ubuntu so rebooting with the drive unplugged **never** hangs boot, plus `.oscar-unmounted-guard` so OSCAR **never** writes to the internal OS disk while unplugged), disables USB autosuspend, installs hotplug auto-catch-up rules, writes laptop copy scripts (`COPY-TO-ANOTHER-DRIVE.bat` and `copy-to-another-drive.sh`), runs the initial seed sync, and enables the 15-minute background scheduler:

**Ubuntu Server 24.04 (formatting `/dev/sdb`):**
```bash
sudo bash oscar.sh usb-backup prepare-drive \
  --device /dev/sdb \
  --mount /srv/oscar-usb-backup \
  --filesystem ntfs \
  --mode continual \
  --interval-minutes 15 \
  --confirm FORMAT
```
*(Already mounted a drive or NAS directory yourself? Pass `--path /srv/oscar-usb-backup` instead of `--device ... --confirm FORMAT`.)*

**Windows 11 (using drive `R:`, formatting as NTFS):**
```powershell
.\oscar.bat usb-backup prepare-drive -DriveLetter R -Format -Confirm FORMAT -Mode continual -IntervalMinutes 15
```
*(Tip: In Windows Disk Management `diskmgmt.msc`, assign a high drive letter like `R:` to the USB SSD once so plugging in USB sticks never shifts its letter.)*

### Step 2B — Option 2: Set Up **Occasional** On-Demand Incremental Backup

Identical fast incremental carrier setup, except **no background timer runs**—backups occur only when you plug in the drive and run `usb-backup sync` (or `attach`):

**Ubuntu Server 24.04:**
```bash
sudo bash oscar.sh usb-backup prepare-drive \
  --device /dev/sdb \
  --mount /srv/oscar-usb-backup \
  --mode occasional \
  --confirm FORMAT
```

**Windows 11:**
```powershell
.\oscar.bat usb-backup prepare-drive -DriveLetter R -Format -Confirm FORMAT -Mode occasional
```

---

## 4. Switching Anytime Between Continual and Occasional Modes

You can switch back and forth between **Continual**, **Occasional**, and **Disabled** at any time in `< 1 second` without reformatting or losing a single historical pack:

```bash
# Ubuntu — switch from Occasional -> Continual (every 15 min + auto-sync on USB plug-in):
sudo bash oscar.sh usb-backup mode continual --interval-minutes 15

# Ubuntu — switch from Continual -> Occasional (manual sync only):
sudo bash oscar.sh usb-backup mode occasional

# Ubuntu — disable automatic sync while preserving all files on the USB drive:
sudo bash oscar.sh usb-backup mode disabled
```

```powershell
# Windows — switch between Continual, Occasional, and Disabled anytime:
.\oscar.bat usb-backup mode continual -IntervalMinutes 15
.\oscar.bat usb-backup mode occasional
.\oscar.bat usb-backup mode disabled
```

Check live backup health, mode, pack counts, free USB space, and latest PostgreSQL LSN anytime:
```bash
sudo bash oscar.sh usb-backup status      # Ubuntu
.\oscar.bat usb-backup status             # Windows
```

---

## 5. Field Data Admin Site-Visit Workflow: Eject → Copy on Laptop → Plug Back In & Auto-Catch-Up

When a data administrator visits a site (even an offline/air-gapped gatehouse) to carry a verified copy of the portal's multi-year archive back on a second drive, **the portal never goes offline (`0.0 seconds` of monitoring interruption)**:

### Step 1 — Safely Eject the USB NVMe SSD from OSCAR
Run one command on the OSCAR server before unplugging the USB cable:

```bash
# Ubuntu:
sudo bash oscar.sh usb-backup eject

# Windows:
.\oscar.bat usb-backup eject
```
What `eject` does automatically:
1. Waits for any in-progress background sync lock to finish cleanly.
2. Runs one final incremental delta sync so the USB SSD is current up to that exact second (pass `--no-sync` / `-NoSync` if you want instant unmount without syncing first).
3. Flushes kernel filesystem buffers and cleanly unmounts/offlines the USB SSD.
4. Prints **`SAFE TO UNPLUG`**. While the USB SSD is unplugged (whether for 15 minutes or 2 weeks), **OSCAR continues recording 100% of RPM counts, alarms, JPEGs, Daily-File CSVs, and OCR reads on its internal NVMe SSD**, and background timer ticks safely log `DETACHED` without writing to the OS disk.

### Step 2 — Plug Into Your Laptop & Copy onto Another Drive
Plug the OSCAR USB NVMe SSD AND your second archive SSD into your field laptop:
- **On a Windows 11 Laptop:**
  Open the `OSCAR_BACKUP` drive and double-click **`COPY-TO-ANOTHER-DRIVE.bat`** (or run `COPY-TO-ANOTHER-DRIVE.bat "E:\Site-Backup-Copy"`). It uses multi-threaded `robocopy /MIR /XO` to copy **only the new daily `.tar` packs added since your last visit** (finishing in seconds after the first copy!) and verifies every snapshot `SHA-256` digest via PowerShell.
- **On a macOS or Linux Laptop:**
  Open Terminal on the mounted `OSCAR_BACKUP` volume and run:
  ```bash
  bash ./copy-to-another-drive.sh "/Volumes/MySecondSSD/Site-Backup-Copy"
  ```
  It uses `rsync` to copy only new daily `.tar` packs and verifies `SHA256SUMS` automatically. *(Dragging and dropping the entire `OSCAR-Backup` folder in Finder / File Explorer also works cleanly.)*
- Safely eject the OSCAR USB NVMe SSD from your laptop when finished.

### Step 3 — Plug the USB NVMe SSD Back Into OSCAR (Automatic Catch-Up!)
- **Ubuntu Server 24.04 (`continual` mode):** Simply plug the USB NVMe SSD back into any USB 3.x port on the OSCAR server—**you do not even need to open a terminal**. Ubuntu's `udev` rule (`99-oscar-usb-backup.rules`) automatically mounts the drive by UUID and immediately triggers `oscar-usb-hotplug-catchup.service`, pulling in **every Parquet generation, Daily-File CSV, retained JPEG, OCR crop, and PostgreSQL update recorded while the drive was unplugged**.
- **Windows 11 (`continual` mode):** Plug the USB NVMe SSD back in; if `eject` offlined the USB disk, run `.\oscar.bat usb-backup attach` (or if already online at its drive letter, the `OSCAR-ContinualBackup` task catches up automatically on its next tick).
- **Manual / `occasional` mode (or immediate terminal confirmation on either OS):**
  ```bash
  sudo bash oscar.sh usb-backup attach    # Ubuntu
  .\oscar.bat usb-backup attach           # Windows
  ```

---

## 6. Restoring or Migrating a Multi-Year (`400+ GiB`) Portal onto a Brand-New Machine

Whether a server fails after 5 years or you are upgrading hardware, you can restore either **directly from the site USB NVMe SSD** or **from the copy you made onto your second SSD**—even onto a **brand-new, uninitialized replacement machine** (Ubuntu ↔ Windows cross-OS migration is also supported because all packs use a platform-neutral POSIX `.tar` + `pg_basebackup` format):

1. **Prepare the replacement host** (extract the matching OSCAR `3.11.0` release or air-gapped offline bundle and run `prepare-host` — **do not** run `oscar init`, because `usb-backup restore` restores the original deployment ID, users, Passkeys, TLS certificates, and secrets automatically!).
2. **Plug in the USB SSD** and provide the separately escrowed `backup-key.txt`:

**Ubuntu Server 24.04 Replacement Machine:**
```bash
sudo bash oscar.sh usb-backup restore \
  --from /mnt/usb-backup \
  --backup-key /secure/escrow/backup-key.txt \
  --confirm RESTORE
```

**Windows 11 Replacement Machine:**
```powershell
.\oscar.bat usb-backup restore `
  -From R:\ `
  -BackupKey C:\secure\escrow\backup-key.txt `
  -Confirm RESTORE
```

What `usb-backup restore` verifies and performs automatically:
1. **Cryptographic Deep Verification:** Authenticates `LATEST` HMAC + `SHA256SUMS.hmac`, hashes **every byte** of every multi-year Parquet and media/CSV `.tar` pack (`--deep`), verifies secret decryptability, and runs `pg_verifybackup` on the PostgreSQL cluster before modifying the target host.
2. **Credentials & Deployment Identity:** Installs `.env`, `secrets/`, `tls/`, and optional Octelium `remote-access/` credentials, creates `oscar_oscar_state` and `oscar_postgres_data` labeled with the original `OSCAR_DEPLOYMENT_ID`, and stamps `.oscar-storage-root` on `OSCAR_ARCHIVE_DIR`.
3. **High-Speed Sequential Extraction:** Streams uncompressed `packs/archive/*.tar` and `packs/state/*.tar` at full NVMe speed (`~10–15 minutes` for a `400 GiB` 5-year 50-lane archive, honoring Day-30 secondary-JPEG pruning via `live-immutable-paths.txt.gz`).
4. **PostgreSQL Timeline Promotion & Service Bring-Up:** Prepares `pg_basebackup` via `oscar-prepare-restore`, promotes PostgreSQL onto a clean timeline (`archive_mode=off`), clears recovery settings, and starts `postgres -> oscar -> gateway`.

---

## 7. Performance & Query Latency Isolation Guarantees

Continual and occasional USB NVMe backups are explicitly engineered so they **do not degrade live RPM ingestion, RTSP video recording, ONNX OCR inference, or UI/report query latency**:

1. **Zero Table Locks & Zero `archive_mode=on` Commit Penalty:**
   - Online `pg_basebackup` streams PostgreSQL via the replication protocol (`START_REPLICATION`) and acquires **zero table locks, row locks, or DDL locks**—live `1 Hz` RPM batch inserts, `30`-minute `osg_*` stage partition drops, operator adjudications, and ConSys/DuckDB queries never wait on a backup.
   - `archive_mode` remains `off`, so PostgreSQL `COMMIT` latency is **`0.0 ms` slower** whether the USB SSD is attached, slow, full, or unplugged for weeks.
2. **Strict Idle CPU & Disk I/O Scheduling (`Nice=19`, `IOSchedulingClass=idle`, `1` CPU Cap):**
   - On Ubuntu 24.04, `oscar-continual-backup.service` and `oscar-usb-hotplug-catchup.service` run under `Nice=19`, `CPUSchedulingPolicy=batch`, `CPUQuota=100%`, and `IOSchedulingClass=idle` (`ionice -c 3`), and every sync container runs with `--cpus=1 --cpu-shares=128` (at most `1` thread out of `16–24`, yielding `100%` of internal NVMe read bandwidth whenever live containers request I/O).
   - On Windows 11, the `OSCAR-ContinualBackup` Scheduled Task runs at `Priority = 8` (background/idle CPU and I/O priority) with `--cpus=1 --cpu-shares=128` and stages `pg_basebackup` inside a native WSL 2 `ext4` volume before streaming sequential `.tar` blocks to the USB drive, avoiding WSL 2 `9p` small-file metadata overhead.
3. **Separate Physical Bus + Uncompressed Sequential `.tar` Streaming (`< 1.5%` Duty Cycle):**
   - All backup **writes** land exclusively on the external USB 3.2 controller, never competing with internal PCIe M.2 NVMe write queues.
   - Because Parquet files (Zstandard) and retained alarm frames (JPEG) are already compressed, `pack-sync` streams uncompressed `.tar` archives (`0` redundant CPU compression) and skips all prior sealed UTC days in `O(1)`, completing a routine 15-minute delta sync in **`~3–15 seconds`** (`< 1.5%` duty cycle; `0.0%` CPU and `0` IOPS for the remaining `14m 45s+` of every interval).
