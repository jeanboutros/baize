# Bai Ze (白泽; pinyin: Báizé)

A Debian package that provisions a rootless [minikube](https://minikube.sigs.k8s.io/) Kubernetes cluster on a Raspberry Pi 5 (arm64), owned by a dedicated locked service account (`baize`) and accessible to human users through a shared kubeconfig.

---

## Installation

### Prerequisites

Install the required system packages first:

```bash
sudo apt update
sudo apt install -y podman curl systemd
```

### Step 1 — Install the package

```bash
sudo dpkg -i baize-kube_1.0_arm64.deb
```

### Step 2 — Reboot if prompted

If the cgroup memory controller is not yet active on your kernel, the installer will patch `/boot/firmware/cmdline.txt` and stop with the following message:

```
╔══════════════════════════════════════════════════════════════╗
║  REBOOT REQUIRED                                            ║
╚══════════════════════════════════════════════════════════════╝
```

Reboot the Pi:

```bash
sudo reboot
```

### Step 3 — Re-run the installer after reboot

```bash
sudo dpkg -i baize-kube_1.0_arm64.deb
```

If the cgroup controller was already active (or after the reboot), the installer completes fully — provisioning the `baize` user, downloading binaries, starting the cluster, and writing the shared kubeconfig.

### Step 4 — Verify the installation

Log out and back in so your shell picks up the `KUBECONFIG` environment variable, then:

```bash
kubectl get nodes
# Expected output:
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   ...   v1.x.x
```

---

## Quick start (summary)

```bash
sudo apt install -y podman curl systemd
sudo dpkg -i baize-kube_1.0_arm64.deb
# reboot if prompted, then re-run the line above
kubectl get nodes
```

To reconfigure minikube:

```bash
sudo -u baize minikube <command>
```

---

## Rebuilding the package

The `.deb` is built from the `debian/` directory using `dpkg-deb`. No compiler is needed — the package contains only shell scripts and documentation.

**Prerequisites on the build machine:**

```bash
# Raspberry Pi OS / Debian
sudo apt install dpkg-dev

# macOS
brew install dpkg
```

**Edit → rebuild cycle:**

```bash
# 1. Edit scripts or docs as needed
# 2. Sync docs into the package tree if you changed them
cp doc/*.md debian/usr/share/doc/baize-kube/

# 3. Rebuild
dpkg-deb --build debian baize-kube_1.0_arm64.deb

# 4. Transfer to the Pi and install
scp baize-kube_1.0_arm64.deb huyang@raspberrypi:~
ssh huyang@raspberrypi "sudo dpkg -i baize-kube_1.0_arm64.deb"
```

**To bump the version**, edit `debian/DEBIAN/control` first:

```
Version: 1.1
```

Then rebuild, optionally renaming the output to match:

```bash
dpkg-deb --build debian baize-kube_1.1_arm64.deb
```

---

## Documentation

| Document | Description |
|---|---|
| [doc/01-cgroups.md](doc/01-cgroups.md) | What cgroups are and how v2 works |
| [doc/02-delegation.md](doc/02-delegation.md) | What cgroup delegation is and how systemd manages it |
| [doc/03-rootless-containers.md](doc/03-rootless-containers.md) | Why rootless Podman and what it requires |
| [doc/04-architecture.md](doc/04-architecture.md) | How this package is structured and why |
| [doc/05-design-decisions.md](doc/05-design-decisions.md) | Every design decision and the reasoning behind it |
| [doc/06-operations.md](doc/06-operations.md) | Day-to-day operations, troubleshooting, and uninstall |

---

## Requirements

- Raspberry Pi 5 running Raspberry Pi OS Bookworm (64-bit)
- arm64 kernel (tested on 6.18+)
- Internet access at install time
- `podman` and `systemd` installed

---

## Package details

| Field | Value |
|---|---|
| Package | baize-kube |
| Version | 1.0 |
| Architecture | arm64 |
| Maintainer | Jean Boutros |
