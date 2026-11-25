# OSCAR Quick Start

OSCAR 3.11.14 deployment and storage operation are supported only on Windows 11 x86-64 with Docker
Desktop/WSL 2 and Ubuntu Server 24.04 x86-64 with Docker Engine/Compose. macOS is limited to source
inspection and non-deployment development; initialization, start, restart, upgrade, and storage
operations fail closed there. Before sizing a host or configuring camera H.264 resolution, frame
rate, and keyframe intervals for `1–50` RPMs and `2–100` cameras (or optional per-lane OCR and
federation hub VMs), review *Recommended hardware and capacity sizing* in
[`DEPLOYMENT.md`](DEPLOYMENT.md#recommended-hardware-and-capacity-sizing).

> **Companion Video Guide:** Watch [Module 01 — Initialize OSCAR Deployment, Admin Credentials & TLS (`01-deployment-init-and-credentials.mp4`)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/01-deployment-init-and-credentials.mp4) ([WebVTT captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/01-deployment-init-and-credentials.vtt)), or browse all 29 captioned workflow guides (`en`, `es`, `fr`, `el`) in [`docs/VIDEO_GUIDES.md`](https://github.com/ORNL/oscar/blob/main/docs/VIDEO_GUIDES.md).
>
> **Try Everything Safely First (`oscar-sandbox`):** After `oscar init`, click **Guided Walkthrough** (*graduation-cap icon* in the top bar) or **Help (`?`)** (*circled question-mark icon*) to highlight console icons or launch the isolated **Hands-On Training Sandbox & Guided Academy** on `:8444` (`sudo bash oscar.sh sandbox start` on Ubuntu; `.\oscar.bat sandbox start` on Windows) to practice lane setup, live Rapiscan/camera monitoring, OCR, WCO UFF X-ray review, and alarm adjudication with zero writes to operational PostgreSQL or Parquet archives, then wipe 100% of practice data with `sandbox stop`. See [`TRAINING_SANDBOX_GUIDE.md`](../../docs/TRAINING_SANDBOX_GUIDE.md).
>
> **Side-by-Side Central Alarm Station (CAS) Rapiscan RPM Installations (`oscar-rpm-proxy`):** When installing OSCAR alongside an existing CAS across `1–50+` Rapiscan RPMs that accept only one TCP connection on `:1600`, run `sudo bash oscar.sh rpm-proxy configure --from-csv <lanes.csv> --start` (Ubuntu 24.04 recommended for `10–50` lanes or Virtual-IP `:1600` mode; `.\oscar.bat rpm-proxy` supported for small Port-Mapped sites) for real-time dual fan-out with `<= 4.0 s` disconnect detection. See [`RPM_EDGE_PROXY_GUIDE.md`](../../docs/RPM_EDGE_PROXY_GUIDE.md).

## Windows 11

1. Choose `offline-full` when Docker Desktop or WSL may need installation. Choose `offline-images` when compatible Docker Desktop, WSL 2, and Docker Compose are already installed and running.
2. Extract the OSCAR ZIP to a local NTFS directory.
3. Assign the server's network-governed static IPv4 address (or configure a router DHCP reservation) before initialization so DHCP lease renewals cannot invalidate generated `tls/server.crt` IP SANs. On an unattended 24/7 Windows 11 host (including mobile/laptop workstations with S0 Modern Standby, USB Gigabit Ethernet, or external USB storage), apply unattended server settings from an Administrator Windows PowerShell 5.1 window before starting continuous lane ingestion:

```powershell
.\oscar.bat prepare-host
.\oscar.bat host-check
```

   On trusted site LANs where remote workstations connect to HTTPS `443`, pass `-ConfigureLanHttpsFirewall` to `prepare-host`. Sites that govern fixed addresses through router DHCP reservations can pass `-AllowDhcpAddress` to `host-check` or `prepare-host`.

4. Double-click `oscar.bat`, approve the Windows administrator prompt, and enter `init` at the `oscar>` prompt. The launcher uses Windows PowerShell 5.1 (`powershell.exe`).
5. Alternatively, for scripted or terminal-based setup, run:

```powershell
.\oscar.bat init
```

6. Enter the deployment hostname, local IANA timezone (for example, `America/Chicago`), and an OSCAR administrator password of at least 14 characters.
   New self-signed installations automatically include the host's active, non-container LAN IPv4
   and Tailscale IPv4/IPv6 addresses in the certificate. If clients will use a stable site-DNS or Tailscale
   MagicDNS name other than the primary hostname, add it with `--tls-san` on Ubuntu or `-TlsSan`
   on Windows during initialization. Once OSCAR converts that initial password into a salted PBKDF2
   hash on first boot, `init` automatically scrubs the plaintext secret from `secrets/oscar-admin-password.txt`
   (replacing it with a non-empty `# CONSUMED_AT_INIT` marker unless `OSCAR_KEEP_BOOTSTRAP_SECRET=true` is set).
7. Open the URL printed by setup, normally `https://oscar.local/` (for the OSCAR Viewer and **Users & Access** at `/users`) or `https://oscar.local/sensorhub/admin`. Sessions with **Keep me signed in until I log out** enabled stay signed in across browser restarts, server reboots, and `oscar upgrade` until explicit **Log Out** or administrator revocation; open **Users & Access (`/users`)** in OSCAR Viewer to add individual `Administrator`, `Operator`, or read-only `Viewer` accounts, bulk-enroll a CSV/Excel user list (`Bulk Enroll`) to generate ready-to-send startup text messages and 1-tap Passkey/Password setup QR codes (`/login/enroll?token=oscar_inv_...`, plus readable fallback codes for phone-free facilities), enroll offline WebAuthn / FIDO2 Passkeys or YubiKeys (changing your local OSCAR password is completely independent of any Octelium Zero-Trust tunnel password), or mint scoped Federation Service Tokens (`oscar_fed_...`) and click **Open Servers Page (Federation Token Mode)** (`/servers?auth=bearer`) on the monitoring/HQ viewer to connect remote nodes.
   - **What LAN & local workstations need for Passkeys:** While PBKDF2 password sign-in works on both domain names and raw LAN IPs, browsers require **(a)** a domain name (such as `https://oscar.local`, or distinct per-node names like `https://oscar.ubuntu` and `https://oscar.win` when running multiple OSCAR servers on the same LAN) mapped in site router Local DNS or client `hosts` files, and **(b)** a trusted HTTPS certificate without bypassed certificate warnings (`certutil -addstore -f Root .\server.crt` on Windows, `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain server.crt` with an `<= 825`-day leaf/CA certificate on macOS, or `update-ca-certificates` + Chrome NSS `certutil -d sql:$HOME/.pki/nssdb` on Linux). If a Passkey-only installation is later moved to a new domain and no administrator remembers a local fallback password, run `sudo bash oscar.sh reset-admin-password` (Ubuntu) or `.\oscar.bat reset-admin-password` (Windows Administrator) on the host to set a local recovery password with zero downtime, sign in once, and enroll a new Passkey for the new domain (see `DEPLOYMENT.md` for bare-metal LUKS2, `sudo`, and SSH hardening).
   - **Optional self-hosted multi-site remote access & centralized SSO (`ORNL/oscar-federation-hub`):** If you want outbound-only HTTPS remote access across firewalled sites plus one place to add or remove users across all federated OSCAR portals (while keeping local offline Passkeys/passwords active on each site), deploy [`ORNL/oscar-federation-hub`](https://github.com/ORNL/oscar-federation-hub) on a central Linux VM (`./oscar-hub.sh init --domain hub.example.org --with-authentik`), register each OSCAR site (`./oscar-hub.sh add-site north-gate --with-trusted-headers`), attach the site's outbound connector (`sudo bash oscar-remote-access.sh configure --domain hub.example.org --service north-gate --token-file north-gate.token` on Ubuntu or `.\oscar-remote-access.ps1 configure` on Windows), and paste the printed OIDC / Trusted Tunnel values into **Users & Access -> Sign-In & SSO Policy**. See `DEPLOYMENT.md` (*Turnkey self-hosted federated remote access & SSO*) for the step-by-step walkthrough.

Setup creates deployment-specific database credentials, defaults `OSCAR_BACKUP_MODE` to `disabled`,
and persists the absolute archive path (and the backup path only when `single` mode is selected) under the sibling `oscar-storage` directory. The legacy-WAL
binding is retained only so an upgrade cannot lose track of already existing compatibility data.
It prepares only the storage required by the selected mode and writes administrator-protected `.oscar-storage-root` identities bound to the
deployment UUID and root kind, configures TLS, and starts OSCAR automatically. Keeping storage outside the
versioned release lets a clean-release upgrade reuse the same data when `.env` is copied. Do not
run a separate launch script after initialization. PostgreSQL runs with `archive_mode=off` and no
external WAL bind.

For offline media, verify it before initialization:

```powershell
.\verify-bundle.ps1
.\oscar.bat init
```

`init` and `upgrade` re-hash the exact bundle inventory on every mutating run before using any
payload; a prior receipt is audit evidence, not a cache that can authorize changed bytes. They also
load the checksum-verified image archive even if same-version tags already exist locally. This
integrity check proves agreement with the co-packaged `SHA256SUMS`, not publisher or release-origin
authenticity, because that manifest is bundled and unsigned. If origin authentication is required,
verify the outer ZIP against an independently trusted detached signature or provenance attestation
before offline transfer. You can run `oscar.bat verify` explicitly at any time. For the images-only
artifact, use `oscar.bat init -Prerequisites existing` to guarantee setup will not launch prerequisite
installers.

If a prerequisite installer requires a Windows restart, restart, sign in to the Windows desktop so
Docker Desktop completes first-time initialization (and accept its license on first launch; you may
then lock the screen with `Win+L`), run `oscar.bat prepare-host` so pre-login Session-0 (`S4U`) boot
startup is registered for future reboots, and run `oscar.bat init` again. Docker Desktop license
review and acceptance are administrator actions; OSCAR never accepts that agreement on the
organization's behalf.

## Ubuntu Server 24.04

For step-by-step instructions tailored to users unfamiliar with Ubuntu or OSCAR—including bootable USB links, **off-site hotel-room Wi-Fi/DHCP staging with 1-command static-IP on-site cutover**, **bare-metal air-gapped USB setup with zero internet and zero DHCP**, declarative `autoinstall`/Netplan/Ansible YAML files, and **discovering unknown camera/RPM IP addresses**—read [`UBUNTU_FIELD_SETUP_GUIDE.md`](../../docs/UBUNTU_FIELD_SETUP_GUIDE.md).

1. Choose `oscar-3.11.14-ubuntu-x86_64-offline-full.zip` for air-gapped sites without internet (or slow hotel Wi-Fi), or `oscar-3.11.14.zip` when installing over fast internet.
2. Prepare the Ubuntu 24.04 host (installs official Docker Engine + Compose v2 from bundled `.deb`s or APT, expands Ubuntu's default `100 GiB` LVM root volume if `--expand-lvm` is passed, masks sleep/suspend, disables automatic unattended-upgrade reboots, bounds offline boot-wait timeouts, and tunes socket buffers):

```sh
sudo bash verify-bundle.sh   # when using ubuntu-x86_64-offline-full
sudo bash oscar.sh prepare-host --expand-lvm --configure-ufw
```

3. **If staging off-site (for example, on hotel Wi-Fi/DHCP before driving to an offline/static-IP site):** identify physical ports, pre-stage your site schematic static IPs *without* dropping hotel internet, and initialize OSCAR (which automatically embeds your staged site IPs into `tls/server.crt`):

```sh
sudo bash oscar.sh identify-nics --watch
sudo bash oscar.sh stage-site-network
sudo bash oscar.sh init
```

   Once you arrive on-site and plug in the site switches, activate the static IPs in one command:

```sh
sudo bash oscar.sh apply-site-network
```

4. **If already connected on-site with static IPs configured**, simply run:

```sh
sudo bash oscar.sh init
```

On a graphical Ubuntu installation, double-click the executable `oscar.sh` launcher to open the same interactive menu. Ubuntu Server administrators use the terminal commands above (and can run `sudo bash oscar.sh discover-devices --interface <NIC>` if RPM or camera IPs are unknown).

## Console Navigation Bar & Visual Icon Guide

Every page and global tool in OSCAR Viewer pairs its text title with a consistent visual icon symbol (which can also be spotlighted live on screen from **Guided Walkthrough** — *graduation-cap icon* — or **Help (`?`)** — *circled question-mark icon*):

| Page / Tool | Route | Visual Icon Symbol | Purpose |
| :--- | :--- | :--- | :--- |
| **Dashboard** | `/` | **Four-tile grid icon** | Live priority alarm queue, compact per-lane health cards, site map & quick adjudication |
| **Events** | `/event-log` | **Warning-triangle (`!`) icon** | Full-database historical event search, CQL filters, Saved Queries & UpSet analytics |
| **Status of Health** | `/health` | **Heart-pulse monitor icon** | Per-lane RPM/camera online status, gamma/neutron faults, tamper (`TT`/`TC`), and extended occupancy |
| **Site Map** | `/map` | **Map-pin icon** | Georeferenced portal lane markers (online vector tiles or offline `.pmtiles` basemaps) |
| **National Summary** | `/national-view` | **Connected-nodes icon** | Multi-lane / multi-site occupancy, alarm, and fault totals |
| **Reports & Analytics** | `/report` | **Bar-chart icon** | 6 report types (`PDF`, `CSV`, `JSON`, `XLSX`) and UpSet co-occurrence analytics |
| **Alarm Transfer** | `/alarm-transfer` | **QR-viewfinder icon** | Offline camera/file import and export of air-gapped QR alarm handoff packages |
| **Users & Access** | `/users` | **Person-and-gear icon** | Administrator user/role management, bulk enrollment QR invites, Passkeys, and SSO policy |
| **USB Backups** | `/usb-backups` | **USB-trident icon** | Zero-downtime continual/occasional USB NVMe incremental backups and safe eject |
| **Runtime Extensions** | `/extensions` | **Puzzle-piece icon** | Hot-swappable OCR rules/models, `.pmtiles` maps, isotope libraries, CAs, policy packs, EML & Cargo UFF |
| **Servers & Nodes** | `/servers` | **Cloud icon** | Local and federated remote OSCAR nodes (`oscar_fed_...` bearer or same-origin session) |
| **Guided Walkthrough** | Top bar | **Graduation-cap icon** | Anytime read-only live refresher (`:443`) and 1-click `:8444` Practice Sandbox launcher |
| **Help (`?`)** | Top bar | **Circled question-mark icon** | 4-language operator quick guide, glossary, 29 captioned videos, icon spotlights & Support Bundle export |
| **Settings** | Top bar | **Gear icon** | Language selector (`en`, `es`, `fr`, `el`), Light/Dark theme, and alarm audio preferences |

## Routine administration

Double-click/open `oscar.bat` or `oscar.sh` with no arguments to keep an administration window open. Enter commands such as `status`, `start`, `stop`, `restart`, `logs -Service oscar`, `support-bundle` (Windows), or `logs --service oscar`, `support-bundle` (Ubuntu). Enter `exit` to close it. Passing arguments directly continues to work for scripts and experienced administrators:

Windows:

```powershell
.\oscar.bat status
.\oscar.bat start
.\oscar.bat stop
.\oscar.bat restart
.\oscar.bat logs -Service oscar
.\oscar.bat support-bundle
```

Ubuntu:

```sh
sudo bash oscar.sh status
sudo bash oscar.sh start
sudo bash oscar.sh stop
sudo bash oscar.sh restart
sudo bash oscar.sh logs --service oscar
sudo bash oscar.sh support-bundle
```

For day-to-day troubleshooting when the web UI is reachable, operators can also select **Help (`?`) -> Export Support Bundle** in the OSCAR Viewer navigation bar to download a redacted `.zip` combining browser diagnostics and rolling server logs; use `support-bundle` from the host CLI whenever containers are degraded or not booting.

The launcher deliberately stops services in dependency order: gateway, OSCAR, then PostgreSQL.
This lets OSCAR finish its bounded journal and database-backed module shutdown before the database
is stopped. Do not replace the launcher command with a multi-service `docker compose restart`.

Fresh deployments cannot create, verify, or restore a coordinated snapshot until an administrator
selects the manual single-snapshot mode and a safe absolute backup path (at least two path
components below its drive or filesystem root) that does not overlap the release or archive roots.
A separate physical drive is recommended for failure isolation, but it is not required. Opt in
through setup:

```powershell
.\oscar.bat upgrade -BackupMode single -BackupDir D:\oscar-storage\backups
```

```sh
sudo bash oscar.sh upgrade --backup-mode single --backup-dir /srv/oscar-backups
```

Protect `secrets/backup-key.txt` separately from snapshot media; it is required to restore encrypted
deployment credentials. Then create and verify the snapshot before an upgrade or retention change:

Windows:

```powershell
.\oscar.bat backup
.\oscar.bat backup-verify -BackupId <ID-printed-by-backup>
.\oscar.bat archive status
.\oscar.bat archive verify
```

Ubuntu:

```sh
sudo bash oscar.sh backup
sudo bash oscar.sh backup-verify <ID-printed-by-backup>
sudo bash oscar.sh archive status
sudo bash oscar.sh archive verify
```

Retention-hold creation prints and persists a resolution label. `GENERATION_EXACT` and `HOT_EXACT`
are exact catalog/row matches; `COLD_RANGE_CONSERVATIVE` protects candidate archive ranges but does
not prove that a possibly sparse observation ID exists. Confirm the event or hold its exact
generation when evidentiary certainty is required. A listed `LEGACY_UNKNOWN` mode is a protective
migration-only label for a pre-3.11.0 observation hold; it does not prove exact observation
existence. Active observation or generation holds also
block Viewer/API datastore removals: a single remove fails visibly and a bulk remove skips held
rows. See `documentation/STORAGE_OPERATIONS.md` before creating or releasing a hold.

`backup` keeps OSCAR quiesced, proves that every query-visible generation has exactly one active
Parquet, manifest, and schema object, verifies each against its catalog checksum,
requires the Parquet object path/checksum and manifest path to match the generation's authoritative
pointers, and rejects a catalog snapshot changed by concurrent activation or purge,
reconciles the archive filesystem, then verifies and HMAC-authenticates the new backup, rejects
unsafe tar members, atomically marks the recovery point `VERIFIED`, and then records protection for
only the exact published daily-file segments present in that accepted snapshot. It creates schema
v2 with required WAL streamed into `postgres/pg_wal` and no cumulative `wal-archive.tar.gz`.
After full acceptance it atomically replaces the HMAC-authenticated `CURRENT` pointer; only then can
the previous non-current fully accepted schema-v2 snapshot be removed. A confirmation failure
leaves the previous `CURRENT` authoritative. The explicit
`backup-verify` command can run with PostgreSQL stopped: it uses a one-shot utility container and
treats the live catalog receipt as optional. Restore additionally requires matching 3.11.14 backup,
current-release, and backed-up release-config identities plus every exact local Compose image.
Plan backup capacity for the old snapshot plus one complete replacement: one snapshot is the
steady-state logical result, not the peak space required while `CURRENT` is changing. If a crash
leaves a non-current published snapshot or private staging debris, the next locked storage command
requires a fully authenticated and accepted schema-v2 `CURRENT`, then removes only non-current
candidates that independently pass the same checks. Schema-v1, failed, partial, unauthenticated,
unaccepted, and incomplete deletion candidates are preserved with warnings. If no `CURRENT` has
ever committed, one uniquely accepted schema-v2 candidate is adopted by reconstructing
authenticated `CURRENT`; multiple accepted candidates are preserved for operator review.
Use `backup-verify` before an audit, copy, or restore. Schema-v1 backups remain explicitly
verifiable/restorable and require their historical WAL tar for authentication, but restore ignores
that external payload because streamed `postgres/pg_wal` is sufficient; v1 is never silently treated as v2.
`backup-prune` is retired, hidden from the menu, and performs no deletion. Keep independently
verified off-host copies under site policy. OSCAR does not provide point-in-time recovery.

Storage commands are mutually exclusive per deployment. A concurrent backup, verify, restore,
archive mutation, archive verification, or export fails immediately with a clear lock message;
wait for the active command rather than bypassing its crash-released, deployment-ID-keyed lock in
the host's administrator-owned runtime/program-data directory. Live commands also reject missing,
foreign, swapped, or unsafe archive identities, optional enabled-backup identities, and mismatched
Docker volumes. The sole
exception is offline-capable `backup-verify`, which does not depend on a running deployment or its
live roots. It is a core-verification operation, not a read-only command: it atomically publishes or
replaces the selected backup's `VERIFIED` marker and normalizes permissions. It does not create
`JOURNAL_CONFIRMED` or change `CURRENT`, so it cannot accept a core-only schema-v2 candidate or make
one restorable. An optional live catalog update occurs only after deployment-volume ownership is
proven.

OSCAR 3.11.14's full storage profile is initialized with a new database and standard configuration.
An upgrade preserves the old `config.json` and PostgreSQL volume, so it does not silently convert a
pre-3.11.0 system to the tiered archive or enable PostgreSQL data checksums. Use a fresh deployment
for the 3.11.14 test systems. Preserve and separately migrate any production history that policy
requires.

If a deliberately retained pre-label deployment uses unlabelled Docker volumes, follow the
one-time `-AdoptLegacyVolumes` (Windows) or `--adopt-legacy-volumes` (Ubuntu) procedure in the
Administrator Guide. Preserve its `.oscar-volume-adoption` receipt with `.env`, `secrets`, and
`tls` during later clean-directory upgrades; never use adoption to join unrelated volumes. Run
upgrades through `oscar.bat` or `oscar.sh`, not a direct `docker compose up`: setup validates the
exact external named volumes before Compose attaches them and force-recreates every service so no
container retains a secret/config bind or Compose provenance from the prior extracted release.
The supported `upgrade` command also stops the application tier and runs the restartable offline
daily-file lifecycle-index migration from the new image. It reads the retained `config.json`, skips
when no Daily File Journal module is configured, and creates no new work markers when the journal is
already indexed. An empty configured journal may receive its metadata. A failure leaves OSCAR
stopped; restart-safe markers created before the failure are retained so the same upgrade can resume.
The shared storage lock prevents a backup or restore from racing the stop, migration, or restart.
Correct the reported storage/permission problem and rerun rather than bypassing the migration.
The OSCAR container remains `starting` until its HTTP service and all top-level auto-start modules
are started and every nested lane RPM/camera has completed its startup attempt. Offline devices do
not prevent access to the Status of Health page; supported setup and storage commands wait only for
the attempt-complete application-readiness signal before returning.

Delete the prior extracted release only after health and container-mount verification, and never
delete a persistent archive, legacy WAL, or backup root preserved by `.env`.
If verified pre-3.11.0 archive or enabled-backup roots are nonempty and have no root marker, the
upgrade also requires the separate one-time `-AdoptLegacyStorageRoots` (Windows) or
`--adopt-legacy-storage-roots` (Ubuntu) switch. It records audited adoption metadata in each archive
or enabled-backup root; it must never be used to claim foreign data or silence a mismatched existing
marker. A retained legacy WAL path is not an active storage root and is neither claimed nor adopted.

The default deployment uses HTTPS port `443`. Setup maps `oscar.local` on the OSCAR host and prints
all LAN/Tailscale URLs covered by a newly generated certificate. Other connecting workstations must
either use one of the printed IP URLs or resolve a printed hostname through DNS/their own hosts
entry. Every workstation must trust the public `tls/server.crt` certificate before login; never
copy `tls/server.key` to a client. See [DEPLOYMENT.md](DEPLOYMENT.md) for certificate trust, DNS,
Tailscale, scoped host-firewall access, log filtering, security verification, and upgrades.
Entering the hostname without `https://` is supported on the default port; the gateway redirects port 80 to HTTPS.

The release's `documentation` directory contains the current deployment guide, operational-view and
Status of Health guides, storage architecture/data-lifecycle/archive/backup/operations guides, and
all four localized operator manuals. Read `documentation/STORAGE_OPERATIONS.md` before relying on
verified staging-partition retirement or removing old cold generations. Official GitHub release artifacts also include the
generated, version-labeled PDF manuals.
