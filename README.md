# Bai Ze (白泽; pinyin: Báizé)

A Debian package that provisions rootless minikube Kubernetes on Raspberry Pi 5, inspired by Bai Ze (白泽; pinyin: Báizé) — the Chinese mythical creature who, entrusted by the Yellow Emperor, catalogued all the ghosts and spirits of the world.

---

## About the Name

Bai Ze (白泽) is a mythical creature from Chinese legend, first recorded in the *Bai Ze Tu* (白泽图, "Diagrams of Bai Ze"), a classical text said to have been compiled during the reign of the Yellow Emperor (c. 2697–2597 BCE). According to the tradition, Bai Ze appeared to the Yellow Emperor and catalogued 11,520 types of ghosts, spirits, and supernatural beings — along with methods to ward them off. The creature is thus associated with comprehensive knowledge, systematic cataloguing, and protection against chaos. This package, which systematically provisions and secures a Kubernetes cluster, is named in that spirit.

## Installation

### Prerequisites

Install the required system packages first:

```bash
sudo apt update
sudo apt install -y podman curl systemd
```

The package itself pulls in the rest of its runtime dependencies via
`Depends:` (gvproxy, virtiofsd, qemu-system-arm, uidmap, crun,
bash-completion) — but `podman` must be installed from the same apt
transaction, hence the explicit line above.

Consumer users need **no sudo** — an admin provisions their kubeconfig with
`sudo baize-kube-add-consumer <username>`. Only administrators need sudo
(for the management scripts and `sudo -u baize` operations).

### Step 1 — Install the package

```bash
sudo dpkg -i baize-kube_<version>_arm64.deb
```

**Optional — size the podman machine.** By default the installer creates a
QEMU machine with 4 CPUs and 6144 MiB of memory (30 GiB disk). On a
memory-constrained Pi you can override this before installation:

```bash
sudo env BAIZE_KUBE_MACHINE_CPUS=2 BAIZE_KUBE_MACHINE_MEMORY=4096 \
    dpkg -i baize-kube_<version>_arm64.deb
```

Minimums: 2 CPUs, 4096 MiB (node plus guest-OS overhead). Invalid or
below-minimum values fail the install immediately with a clear error.

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

### Step 3 — Reboot and let the installer complete automatically

After reboot, a oneshot systemd service (`baize-kube-reboot.service`) runs automatically and completes the installation — provisioning the `baize` user, downloading binaries, starting the cluster, and writing the admin kubeconfig. No manual re-run of `dpkg -i` is needed.

**Check that installation completed successfully:**

```bash
systemctl status baize-kube-reboot
# Look for "Active: inactive (dead)" with no errors in the log output.
# A successful run shows the service exited cleanly after completing all steps.
```

If the cgroup controller was already active during the initial install, the installer completes fully in a single pass — no reboot or service is needed.

### Step 4 — Verify the installation

Log out and back in so your shell picks up the `KUBECONFIG` environment variable, then:

```bash
kubectl get nodes
# Expected output:
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   ...   v1.x.x
```

Run a one-shot busybox test pod (created, runs, and is auto-deleted by `--rm`):

```bash
kubectl run baize-test --image=busybox:latest --rm -it \
    --restart=Never -- echo OK
```

For everything else — adding users, checking access, troubleshooting
kubectl, or understanding the internals — run the built-in guide:

```bash
baize-kube-help
```

---

## Quick start (summary)

```bash
sudo apt install -y podman curl systemd
sudo dpkg -i baize-kube_<version>_arm64.deb
# reboot if prompted — installation completes automatically on next boot
kubectl get nodes
```

To reconfigure minikube, run commands as `baize` with its runtime
environment (see `baize-kube-help` section 5 for a ready-made `bk` function):

```bash
sudo -u baize env XDG_RUNTIME_DIR=/run/user/$(id -u baize) \
    CONTAINER_HOST=unix:///run/user/$(id -u baize)/podman/minikube-api.sock \
    minikube <command>
```

### Management scripts

Management scripts require `sudo` because they access `/etc/baize-kube/admin-kubeconfig` (owned by `root:baize-admins`, mode 640):

```bash
# Add a consumer user to the cluster
sudo baize-kube-add-consumer <username>

# Show the full user guide (access checks, troubleshooting, internals)
baize-kube-help

# List all provisioned consumers
sudo baize-kube-list-consumers

# Remove a consumer
sudo baize-kube-remove-consumer <username>

# Update a consumer's kubeconfig
sudo baize-kube-update-kubeconfig <username>

# Regenerate the shared admin kubeconfig (after cluster recreation)
sudo baize-kube-update-admin-kubeconfig
```

---

## Building and Installing

The `.deb` is built from the `debian/` directory using `dpkg-deb`. No compiler is needed — the package contains only shell scripts and documentation.

### Prerequisites

```bash
# Raspberry Pi OS / Debian
sudo apt install dpkg-dev shellcheck lintian bats

# macOS (build only — install must be done on arm64 Debian)
brew install dpkg
```

### Using make (recommended)

```bash
# Lint and test before building
make lint
make test

# Build the package
make build
# Output: baize-kube_<version>_arm64.deb

# Install on the target Pi
make install
# Or manually:
# sudo dpkg -i baize-kube_*.deb
```

The `make build` target automatically:
- Copies documentation into the package tree
- Derives the version from git tags (falls back to `1.0.0`)
- Injects the version into `debian/DEBIAN/control`
- Builds with `--root-owner-group` for correct file ownership

Other useful targets:

| Target | Description |
|--------|-------------|
| `make lint` | Run shellcheck on all scripts and lintian on the package |
| `make test` | Run the bats test suite (unit + integration) |
| `make clean` | Remove the built .deb and generated doc directory |

### Manual build

If you prefer to build without make:

```bash
# 1. Copy documentation into the package tree
mkdir -p debian/usr/share/doc/baize-kube
cp doc/*.md debian/usr/share/doc/baize-kube/

# 2. Build (version must match debian/DEBIAN/control)
dpkg-deb --build --root-owner-group debian baize-kube_<version>_arm64.deb

# 3. Install on the target Pi
sudo dpkg -i baize-kube_<version>_arm64.deb
```

**To bump the version**, edit `debian/DEBIAN/control` first:

```
Version: <new-version>
```

Then rebuild, optionally renaming the output to match:

```bash
dpkg-deb --build --root-owner-group debian baize-kube_1.1_arm64.deb
```

### Transferring to a Pi

```bash
scp baize-kube_*.deb <user>@<host>:~
ssh <user>@<host> "sudo dpkg -i baize-kube_*.deb"
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
| [doc/07-installation.md](doc/07-installation.md) | Detailed installation guide with prerequisites, step-by-step instructions, and troubleshooting |

---

## Requirements

- Raspberry Pi 5 running Raspberry Pi OS Bookworm (64-bit)
- arm64 kernel (tested on 6.18+)
- Internet access at install time
- `podman` and `systemd` installed (the package adds: gvproxy, virtiofsd,
  qemu-system-arm, uidmap, crun, bash-completion)
- ~10 GB free disk for the podman machine image and minikube node image

---

## Package details

| Field | Value |
|---|---|
| Package | baize-kube |
| Version | (from git tag via `make build`) |
| Architecture | arm64 |
| Maintainer | Jean Boutros |
