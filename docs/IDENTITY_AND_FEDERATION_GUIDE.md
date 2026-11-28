# OSCAR 3.12.2 Identity, Offline Passkeys, SSO & Multi-Node Federation Guide

OSCAR 3.12.2 manages operator identities, offline phishing-resistant WebAuthn Passkeys, optional enterprise or self-hosted SSO, and multi-site data federation directly from **Users & Access (`/users`)** and **Servers (`/servers`)** — with zero external internet dependency for local operations.

> **Companion References:**
> - **Video Walkthroughs:** Watch [Module 19 — User Accounts, Roles, Passkeys & Access Management](https://github.com/ORNL/oscar-video-guides/blob/main/videos/19-viewer-users-passkeys-and-access.mp4), [Module 20 — Multi-Node Federation, Vehicle Search & Reports](https://github.com/ORNL/oscar-video-guides/blob/main/videos/20-multi-node-federation-vehicle-search-and-report.mp4), and [Module 21 — Federated SSO, Passkey Onboarding & Revocation](https://github.com/ORNL/oscar-video-guides/blob/main/videos/21-federated-sso-passkey-onboarding-and-revocation.mp4) in [VIDEO_GUIDES.md](VIDEO_GUIDES.md).
> - **Host CLI & OpenSSL Reference:** See [Administrator Guide — Authentication, Passkeys, SSO & Host Hardening](../dist/release/DEPLOYMENT.md#authentication-offline-passkeys-persistent-sessions-sso--remote-access-tunnel) and [`ORNL/oscar-federation-hub`](https://github.com/ORNL/oscar-federation-hub).

---

## 1. Roles, Operational Views & Session Policy (`/users`)

Open **Users & Access (`/users`)** in OSCAR Viewer. Administrators see six tabs: **My Account & Passkeys**, **Users & Roles**, **Federation Tokens**, **Sign-In & SSO Policy**, **Recovery**, and **System Update**. Standard `Operator` and `Viewer` accounts see **My Account & Passkeys** for self-service Passkey and password management.

### 1.1 Built-In Roles

| Role | Scope & Permissions | Operational View Restriction (`allowedViews`) |
| :--- | :--- | :--- |
| **`Administrator`** | Full OSCAR Viewer, SensorHub Admin (`/sensorhub/admin`), `/users`, `/extensions`, `/usb-backups`, `/servers`, and System Update access. Protected by last-admin lockout prevention (the final enabled Administrator cannot be deleted or demoted). | Unrestricted (**All Lanes** + every configured view). |
| **`Operator`** | Live monitoring, alarm adjudication, secondary spectroscopy upload, report generation, QR alarm transfer, and multi-pass vehicle search. Zero host OS, container, or `/users` administrative access. | Optional. Leave blank for all lanes, or assign one or more Operational View keys (`north-gate`, `secondary`). |
| **`Viewer`** | Read-only monitoring, maps, Status of Health, event history, and reports (cannot submit adjudications or modify settings). | Optional. Enforced server-side in `BasicSessionAuthenticator` (`/view/<slug>`) and in OSCAR Viewer (omits **All Lanes** from the top-bar switcher). |

### 1.2 Persistent Console Sessions vs. Timed Shift Kiosks

Fresh OSCAR 3.12.2 deployments default to **"Stay Signed In Until Logout"** (`idleTimeoutSeconds = 0`, `absoluteTimeoutSeconds = 0`, `persistSessions = true`, `allowKeepSignedIn = true`, `persistentCookieMaxAgeSeconds = 31536000`) so unattended 24/7 gatehouse wallboards survive browser restarts, host reboots, and `oscar upgrade` without forcing repeated sign-ins.

- Only **SHA-256 digests** of active `OSCAR_SESSION` cookies are written to `/var/lib/oscar/.moduledata/oscar-identity.json` (`0600`) — never plaintext session tokens.
- For **shared shift kiosks** where operators rotate at the same keyboard, open **Users & Access -> Sign-In & SSO Policy** and set explicit timeouts (for example `1800 s` idle / `28800 s` absolute) or disable **Allow Keep Me Signed In**.

---

## 2. User Enrollment: Individual Accounts, Bulk CSV & 1-Tap QR Invites

### 2.1 Bulk CSV / Paste Onboarding (Up to `500` Users)

In **Users & Access -> Users & Roles**, click **Bulk Enroll (CSV / Paste)** to create up to `500` accounts in one batch using four columns (`username, role, display_name, views`):

```csv
username,role,display_name,views
j.rivera,operator,Jordan Rivera,north-gate;secondary
a.chen,viewer,Alex Chen,north-gate
m.patel,operator,Maya Patel,south-gate
```

### 2.2 Single-Use QR Invites & Phone-Free Fallback Codes

For every newly enrolled user, OSCAR generates:
1. **A single-use QR code and setup URL (`/login/enroll?token=oscar_inv_...`):** Safe against messaging link-preview crawlers (`GET` is strictly read-only and never consumes the invite token). Scanning or opening the link lets the operator enroll a 1-tap **Passkey** or set their private local PBKDF2 password (`>= 14` characters) and lands them directly in their assigned Operational View.
2. **A ready-to-send startup text and printable handout card.**
3. **A readable fallback enrollment code** for secure phone-free facilities (`/login/password-change`).

---

## 3. Offline WebAuthn / FIDO2 Passkeys on Local & LAN Networks

OSCAR verifies WebAuthn / FIDO2 Passkeys (`ES256` and `RS256` — Windows Hello, Touch ID, Face ID, and USB/NFC security keys such as YubiKey) **100% locally with zero internet dependency**.

Browsers enforce two strict security requirements before exposing WebAuthn (`navigator.credentials.create` / `get`):

1. **Access via a domain name (never a raw IP address):**
   - Local PBKDF2 username + password sign-in continues working over raw IPv4 URLs (`https://198.51.100.10/`), but browsers disable Passkeys on IP literals.
   - Always open OSCAR via a hostname (for example `https://portal-north.example.org`). On multi-node LANs, assign a **distinct hostname per server** during `init` (`--hostname` / `-Hostname`) so TLS certificates and WebAuthn Relying Party IDs (`rpId`) never collide.
   - Configure site DNS `A` records on your router/DNS server (recommended for multiple workstations and phones) or map the hostname in client `hosts` files on air-gapped LANs. `oscar init` automatically adds `127.0.0.1 <hostname>` locally on the OSCAR host itself so host-local Passkeys work even with the network cable unplugged.
2. **A trusted HTTPS certificate with zero browser warnings (`<= 825`-day leaf rule for Apple macOS / iOS):**
   - Clicking past a self-signed certificate warning disables WebAuthn in Chrome, Edge, and Safari.
   - Apple macOS and iOS reject leaf TLS server certificates whose validity exceeds `825` days (`ERR_CERT_VALIDITY_TOO_LONG`). Whenever macOS/iOS browsers or multiple LAN nodes are used, issue an **`820`-day leaf certificate** signed by a one-time site Root CA (`oscar-lan-root-ca.crt`), shred the Root CA private key immediately, and install `oscar-lan-root-ca.crt` once into each client trust store:
     - **Windows (elevated PowerShell):** `certutil -addstore -f Root .\oscar-lan-root-ca.crt`
     - **Ubuntu / Linux:** copy to `/usr/local/share/ca-certificates/oscar-site.crt`, run `sudo update-ca-certificates`, and for Chromium/Chrome NSS trust run `certutil -d "sql:$HOME/.pki/nssdb" -A -t "CT,C,C" -n "OSCAR Site" -i ./oscar-lan-root-ca.crt` (`libnss3-tools`).
     - **macOS:** `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./oscar-lan-root-ca.crt`
   - See [Administrator Guide — Enabling Local and LAN WebAuthn Passkeys](../dist/release/DEPLOYMENT.md#enabling-local-and-lan-webauthn-passkeys-multi-node-hostnames-dnshosts--tls-trust) for the complete `openssl` site Root CA command block and zero-data-loss hostname rename steps.

> **Multi-URL Passkey Tip:** Because WebAuthn binds each Passkey to its domain (`rpId`), a Passkey registered on a local LAN URL (`https://portal-north.lan`) signs in across the LAN, while connecting remotely over a Zero-Trust tunnel domain (`https://north-gate.hub.example.org`) simply prompts the user once to click **Add a Passkey or Security Key** on that tunnel URL under the same OSCAR account.

---

## 4. Enterprise OIDC SSO & Turnkey Self-Hosted Federation Hub

Open **Users & Access -> Sign-In & SSO Policy** to connect OSCAR to an existing enterprise IdP (Entra ID, Okta, Keycloak) or the turnkey self-hosted **[`ORNL/oscar-federation-hub`](https://github.com/ORNL/oscar-federation-hub)** (Octelium Zero-Trust tunnel + Authentik browser SSO console).

### 4.1 Corporate / Authentik OIDC + PKCE Settings (`BasicSessionConfig`)

| Setting | Default / Example | Notes |
| :--- | :--- | :--- |
| **Enable Organization OIDC SSO (`oidcEnabled`)** | `false` | Surfaces **Sign in with Organization SSO** on `/login` alongside local Passkeys and passwords. |
| **OIDC Provider Label (`oidcProviderName`)** | `Organization SSO` | Custom button label (e.g., `Agency SSO`, `Okta`, `Entra ID`, `Authentik`). |
| **OIDC Issuer URL (`oidcIssuerUrl`)** | `https://auth.hub.example.org/application/o/oscar-federation-sso/` | HTTPS issuer serving `/.well-known/openid-configuration` and JWKS keys. |
| **OIDC Client ID / Secret (`oidcClientId`, `oidcClientSecret`)** | `oscar-federation-hub` / optional secret | Supports both confidential clients and public PKCE clients (blank secret). |
| **OIDC Scopes (`oidcScopes`)** | `openid profile email groups` | Space-delimited scopes requested on login. |
| **Admin / Operator / Default Role Mapping** | `oscar-admins` / `oscar-operators` / `viewer` | Maps IdP `groups` claims cleanly to OSCAR `Administrator`, `Operator`, or fallback `Viewer` (`oidcDefaultRole`). |
| **OIDC Custom CA Certificate Path (`oidcTrustedCaCertificatePath`)** | *(blank)* | Optional mounted PEM file or directory of private-CA `.crt`/`.pem` roots for internal PKI IdPs (in addition to certs managed in **Extensions -> Trusted Certificates**). |
| **External SSO Admin Console URL (`externalIdentityConsoleUrl`)** | `https://auth.hub.example.org/if/admin/` | Adds a 1-click **Open Federated User Console** shortcut at the top of **Users & Roles**. |

### 4.2 Zero-Click Octelium Tunnel Header SSO & Offline Local Coexistence

Sites connected via `oscar-remote-access.sh` / `oscar-remote-access.ps1` to an Octelium Zero-Trust hub (`ORNL/oscar-federation-hub`) can optionally enable **Trusted Tunnel SSO** (`trustedTunnelSsoEnabled = true`):

- Verifies `X-Octelium-User` and optional `X-Octelium-Groups` **only** when accompanied by the configured `>= 16`-character `X-Oscar-Tunnel-Secret` header (`trustedTunnelSharedSecret`) injected by the local tunnel sidecar.
- Maps `oscar-admins` -> `Administrator`, `oscar-operators` -> `Operator`, and optionally auto-provisions unrecognized tunnel identities as read-only `Viewer` (`trustedTunnelAutoProvisionViewer`).
- **Two strict operational safety guarantees:**
  1. **Local accounts are never overwritten:** Central `oidc` and `tunnel` profiles never overwrite `authSource = "local"` accounts, so local Passkeys and PBKDF2 passwords continue working uninterrupted on the LAN whenever WAN connectivity drops.
  2. **Tunnel uptime is independent of human passwords:** `oscar-tunnel` authenticates to the Hub with its own workload ServiceAccount token (`$STORAGE_ROOT/remote-access/octelium-token.txt`); resetting a user's OSCAR password never interrupts remote tunnel connectivity, and `oscar upgrade` automatically keeps `oscar-tunnel:${OSCAR_VERSION}` rebuilt and synced.
- **Zero-Trust Remote Practice Sandbox (`https://<site>-sandbox.<hub>`):** The same single outbound `oscar-tunnel` sidecar automatically exposes each site's ephemeral `:8444` Practice Sandbox over standard HTTPS `:443` with shared parent-domain Passkeys and SSO while keeping `/sensorhub/admin` blocked on the operational `<site>.<hub>` endpoint (see [Training Sandbox Guide](TRAINING_SANDBOX_GUIDE.md)).

---

## 5. Multi-Node Data Federation with Scoped Service Tokens (`oscar_fed_*`)

Never share a human Administrator password across servers to link remote portals into a headquarters or regional OSCAR Viewer. Instead, use revocable, least-privilege **Federation Service Tokens (`oscar_fed_<shortId>_<secret>`)**:

### Step 1 — Mint a Scoped Token on the Monitored (Remote) Node
1. Sign in as an `Administrator` on the remote site and open **Users & Access (`/users`) -> Federation Tokens**.
2. Create a token named for the consuming headquarters/viewer (for example `hq-national-monitor`), choose the minimum required role:
   - **`Viewer`** — for read-only **National View (`/national-view`)**, remote alarm/media visibility, **Multi-Pass Vehicle ID Search**, and **`VEHICLE_INCIDENT`** report generation.
   - **`Operator`** — additionally permits remote **Linked Adjudication** across correlated passes from the central console.
3. Copy the minted `oscar_fed_<shortId>_<secret>` value immediately (the raw secret is shown once; only its cryptographic hash is stored).

### Step 2 — Register the Remote Node on the Monitoring / HQ Viewer (`/servers`)
1. Open **Servers (`/servers?auth=bearer`)** (or click **Open Servers Page (Federation Token Mode)** directly from the token banner).
2. Click **Add Server**, enter the remote node's hostname (for example `north-gate.hub.example.org` or its LAN FQDN), port `443`, `HTTPS`, and select **Authentication Method: Federation Service Token**.
3. Paste the `oscar_fed_...` token and save.

OSCAR uses the single `oscar_fed_...` token to authenticate both ConSys/Bucket HTTP `Bearer` requests and HiveMQ WebSocket MQTT connections (`svc-fed-<shortId>`). Disabling or offboarding a human employee never interrupts site-to-central telemetry, and revoking a compromised server requires one click in **Federation Tokens** on the monitored node.

### Cross-Node Capabilities Unlocked
Once registered in `/servers`, operators on the monitoring console immediately gain:
- **National View (`/national-view`):** Aggregated site statistics across all connected nodes.
- **Multi-Pass Vehicle ID Search & `Compare Passes` (`/event-log`):** Cross-node container/plate search (`200` results per server, `16` overlaid traces/thumbnails) correlating a truck or shipping container across multiple portals.
- **Cross-Node Linked Adjudication & `VEHICLE_INCIDENT` Reports:** Apply linked dispositions across matched passes (when the peer token holds `Operator` scope) and generate consolidated `PDF` / `CSV` / `JSON` / `XLSX` `VEHICLE_INCIDENT` reports.

---

## 6. Break-Glass Admin Recovery & Host Security Posture

If an OSCAR deployment is restored onto a new domain (invalidating Passkeys bound to the old `rpId`) or all Administrators lose access, an authenticated host OS administrator can recover a local PBKDF2 password (`>= 14` characters) with **zero portal downtime**:

```sh
# Ubuntu Server 24.04 (interactive hidden TTY prompt; use --password-stdin for automation)
sudo bash oscar.sh reset-admin-password [--user admin] [--must-change]
```

```powershell
# Windows 11 + WSL 2 (elevated PowerShell; SecureString prompt or -PasswordStdin)
.\oscar.bat reset-admin-password [-User admin] [-MustChange]
```

`reset-admin-password` intentionally rejects plaintext `--password` / `-Password` arguments, applies atomically while OSCAR is running, clears login rate-limit lockouts, revokes active sessions for that user, preserves all existing users, Operational Views, and Passkeys, and appends an indelible `BREAK_GLASS_PASSWORD_RESET` record to `/var/lib/oscar/.moduledata/security-break-glass-audit.log`, OSCAR `WARN` logs, and host `syslog` / Windows Application Event Log.

Because host OS root/Administrator privilege controls `reset-admin-password` and disk state, production portals should always enforce all six host defense-in-depth layers documented in **[Administrator Guide — Securing Host Privilege, At-Rest Storage & Bare-Metal Autoinstall](../dist/release/DEPLOYMENT.md#securing-host-privilege-at-rest-storage--bare-metal-autoinstall-deployments)** (`UEFI Secure Boot` + supervisor password, `LUKS2` / `BitLocker`, `--require-sudo-password` with zero `docker` group membership, `--ssh-keys-only` / UFW SSH scoping, unprivileged read-only containers, and `sudo bash oscar.sh host-check --strict`).
