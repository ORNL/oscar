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
| `site-network.example.env` | Simple fill-in-the-blanks worksheet for staging site static IPs in a hotel room (`sudo bash oscar.sh stage-site-network --config ubuntu/site-network.env`) without dropping hotel Wi-Fi/DHCP. |
| `netplan/01-single-nic-static.yaml.example` | Netplan v2 template when Operator PCs, RPMs, and cameras share a single Ethernet switch (with or without a default gateway). |
| `netplan/02-dual-nic-operator-and-sensor-vlan.yaml.example` | Netplan v2 template for 2-NIC portal servers: Port 1 = Operator/Site LAN, Port 2 = Isolated air-gapped RPM & camera switch (`optional: true`, no gateway). |
| `autoinstall/user-data.yaml` & `autoinstall/meta-data` | Zero-touch declarative Ubuntu Server 24.04 `cloud-init` installer config (`CIDATA` USB label or PXE): allocates `100%` of the NVMe (`sizing-policy: all`), skips Snap Docker, enables SSH, and prevents offline boot hangs. |
| `ansible-site-hosts.yml` | Optional single-file Ansible playbook to converge one or multiple Ubuntu 24.04 hosts remotely over SSH from a laptop. |
