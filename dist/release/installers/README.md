# Offline prerequisite bundle

The official offline bundle builders place vendor-supplied, checksum-verified Windows 11 or Ubuntu 24.04 LTS installers in
this directory. Installer binaries are deliberately not stored in source control.

```text
installers/
  windows-x86_64/
    Docker Desktop Installer.exe
    wsl.<version>.x64.msi
  ubuntu-24.04-x86_64/
    docker-ce*.deb, containerd.io*.deb, docker-compose-plugin*.deb, ...
    host-tools/
      chrony*.deb, ethtool*.deb, nmap*.deb, arp-scan*.deb, jq*.deb, ...
```

OSCAR 3.11.0 storage deployment is not supported on macOS; no macOS prerequisite
payload is part of a supported release bundle.

Run `tools/offline/build-offline-bundle.ps1 -BundleProfile Both -CreateArchive` to create both Windows production artifacts (`offline-full` and `offline-images`, pinned in `tools/offline/components.windows-x86_64.json`), and run `tools/offline/build-ubuntu-offline-bundle.sh --create-archive` on Linux with Docker available to create the air-gapped Ubuntu 24.04 LTS full bundle (`oscar-<version>-ubuntu-x86_64-offline-full.zip`, recording exact `.deb` versions and SHA-256 digests in `installers/components.ubuntu-24.04-x86_64.json`). The offline OSCAR CLI never downloads software or container images.

Only redistribute installers when the vendor license permits it. Docker Desktop requires a paid subscription for government entities; the OSCAR CLI does not accept that agreement on the administrator's behalf. Document the source URL, version, architecture, SHA-256 digest, download date, and license with every approved release bundle.
