# 07 — Installation Guide

## Prerequisites

### Hardware

- Raspberry Pi 5 (arm64)
- Raspberry Pi OS Bookworm (64-bit)
- Internet access during installation

### System packages

Install the required system packages before installing `baize-kube`:

```bash
sudo apt update
sudo apt install -y podman curl systemd
```

The package pulls in its remaining runtime dependencies via `Depends:`
(gvproxy, virtiofsd, qemu-system-arm, uidmap, crun, bash-completion).
`podman` itself must come from the same apt transaction, hence the
explicit line above.

**Disk space:** the podman machine image (~600 MB download) plus the
minikube node image and cluster state need roughly 10 GB free.

### Consumer users

Consumer users (human users who will access the cluster) need **no sudo and
no special privileges**. Their access is a per-user kubeconfig provisioned
by an admin with `sudo baize-kube-add-consumer <username>` — they simply
run `kubectl` as themselves.

Only **administrators** need sudo (for the management scripts and
`sudo -u baize` cluster operations, which are auditable). Do NOT add
consumers to the `sudo` group — that would dissolve the two-group
security model entirely (see doc/05).

---

## Pre-installation: Consumer configuration

Before installing, create the consumer configuration file at `/etc/baize-kube/consumers.conf`. This file lists the human users who should have access to the cluster.

```bash
sudo mkdir -p /etc/baize-kube
sudo nano /etc/baize-kube/consumers.conf
```

Add one username per line. Lines starting with `#` are comments:

```
# baize-kube consumer users
alice
bob
```

If this file is not present and the install is running non-interactively (e.g. via Ansible or a script), the installer will fail with a clear error message. There is no fallback to "all users" — consumer access must be explicitly declared.

---

## Installation

### Step 1 — Install the package

```bash
sudo dpkg -i baize-kube_<version>_arm64.deb
```

**Optional — size the podman machine before install.** The installer
creates a QEMU podman machine for the `baize` user (default 4 CPUs,
6144 MiB memory, 30 GiB disk). On memory-constrained boards, override
with environment variables (minimums are minikube's requirements:
2 CPUs, 4096 MiB (node + guest OS) — invalid values fail the install immediately):

```bash
sudo env BAIZE_KUBE_MACHINE_CPUS=2 BAIZE_KUBE_MACHINE_MEMORY=4096 \
    dpkg -i baize-kube_<version>_arm64.deb
```

The installer will:

1. Check network connectivity to the download servers
2. Check if the cgroup memory controller is active
3. Configure cgroup delegation for all user sessions
4. Create the `baize` service account, `baize-admins` group, and `baize-consumers` group
5. Add the users from `consumers.conf` to the `baize-consumers` group
6. Add the first valid user to the `baize-admins` group (initial cluster admin)
7. Download `minikube` and `kubectl` binaries
8. Install management scripts to `/usr/bin/`
9. Enable systemd lingering for `baize`
10. Configure minikube for rootless Podman
11. Install and enable the minikube systemd user service
12. Start the minikube cluster
13. Export the admin kubeconfig to `/etc/baize-kube/admin-kubeconfig`
14. Install the shell profile snippet for admins

### Step 2 — Reboot if prompted

If the cgroup memory controller is not yet active on your kernel, the installer will:

1. Patch `/boot/firmware/cmdline.txt` to add `cgroup_memory=1 cgroup_enable=memory`
2. Install a one-shot systemd service (`baize-kube-reboot.service`)
3. Create a flag file at `/var/lib/baize-kube/needs-reboot`
4. Exit with a non-zero status, leaving the package in "Half-Configured" state

You will see:

```
╔══════════════════════════════════════════════════════════════╗
║  REBOOT REQUIRED                                            ║
║                                                             ║
║  The kernel boot parameters have been updated to enable     ║
║  the cgroup memory controller, which is required for        ║
║  rootless Podman to enforce memory limits on containers.    ║
║                                                             ║
║  Please reboot now:                                         ║
║    sudo reboot                                              ║
║                                                             ║
║  Installation will complete automatically on next boot.    ║
║  No manual re-run of dpkg is required.                     ║
╚══════════════════════════════════════════════════════════════╝
```

Reboot the Pi:

```bash
sudo reboot
```

### Step 3 — Automatic completion after reboot

On the next boot, the `baize-kube-reboot.service` runs automatically. It:

1. Verifies the cgroup memory controller is now active
2. Runs `dpkg --configure baize-kube` to complete the deferred installation
3. Disables and removes the one-shot service
4. Removes the flag file

The entire installation completes without any manual intervention. After the service runs, the cluster is fully provisioned and running.

You can verify the service ran by checking the journal:

```bash
journalctl -u baize-kube-reboot.service
```

---

## Post-installation verification

### Check cgroup controllers

```bash
cat /sys/fs/cgroup/cgroup.controllers
# Expected: cpuset cpu io memory pids
```

### Check the baize user service and podman machine

```bash
sudo -u baize env XDG_RUNTIME_DIR=/run/user/$(id -u baize) \
    systemctl --user status minikube
sudo -u baize env XDG_RUNTIME_DIR=/run/user/$(id -u baize) \
    podman machine ls
# The machine "minikube" must be in state "Running"
```

### Check the cluster

Log out and back in so your shell picks up the `KUBECONFIG` environment variable, then:

```bash
kubectl get nodes
# Expected output:
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   ...   v1.x.x
```

### Check kubeconfig is set

```bash
echo $KUBECONFIG
# Expected (for admins): /etc/baize-kube/admin-kubeconfig
# Expected (for consumers): (empty — uses default ~/.kube/config)
```

If you are an admin and `KUBECONFIG` is not set, log out and back in, or source it manually:

```bash
export KUBECONFIG=/etc/baize-kube/admin-kubeconfig
```

---

## Adding consumers after installation

> **Note:** All management scripts (`baize-kube-add-consumer`, `baize-kube-list-consumers`, `baize-kube-remove-consumer`, `baize-kube-update-kubeconfig`) require `sudo` because they access `/etc/baize-kube/admin-kubeconfig`, which is owned by `root:baize-admins` with mode 640. Only root (via sudo) can read this file.

### Group membership

To give another user the right to be provisioned for cluster access:

```bash
sudo usermod -aG baize-consumers <username>
```

The user must log out and back in for the group change to take effect.

### Provisioning a consumer

After adding a user to the `baize-consumers` group, an admin must explicitly provision them with Kubernetes access:

```bash
sudo baize-kube-add-consumer <username>
```

This creates:
- A per-user Kubernetes ServiceAccount (`consumer-<username>`)
- A long-lived token Secret
- RBAC bindings (default: `view` ClusterRole, read-only cluster-wide)
- A kubeconfig at `~<username>/.kube/config` (mode 600, owned by the user)

The consumer can then run `kubectl` commands directly — no `KUBECONFIG` environment variable is needed because kubectl uses `~/.kube/config` by default.

### Provisioning with specific roles

```bash
# Read-only access to all namespaces (default)
sudo baize-kube-add-consumer alice

# Read-write access to the 'dev' namespace
sudo baize-kube-add-consumer bob --role edit --namespace dev

# Full admin access to the 'staging' namespace
sudo baize-kube-add-consumer carol --role admin --namespace staging

# Custom ClusterRole
sudo baize-kube-add-consumer dave --cluster-role my-custom-role
```

### Listing provisioned consumers

```bash
sudo baize-kube-list-consumers
```

Output:
```
USERNAME             ROLE         NAMESPACE            KUBECONFIG
--------             ----         ---------            ----------
alice                view         (cluster)            /home/alice/.kube/config
bob                  edit         dev                  /home/bob/.kube/config
carol                admin        staging              /home/carol/.kube/config
```

### Deprovisioning a consumer

```bash
sudo baize-kube-remove-consumer <username>
```

This removes the ServiceAccount, token Secret, RBAC bindings, and kubeconfig. To also remove the user from the `baize-consumers` group:

```bash
sudo baize-kube-remove-consumer <username> --remove-group
```

### Updating a consumer's kubeconfig

If the cluster is reconfigured or a token is rotated, regenerate the kubeconfig:

```bash
sudo baize-kube-update-kubeconfig <username>
```

### Verifying a consumer's permissions

```bash
kubectl auth can-i --list --as=system:serviceaccount:default:consumer-<username>
```

---

## Troubleshooting

### cgroup memory controller not active after reboot

Verify the cmdline.txt patch was applied:

```bash
cat /boot/firmware/cmdline.txt | grep -o 'cgroup_enable=memory'
```

If absent, apply manually:

```bash
sudo nano /boot/firmware/cmdline.txt
# Add to the end of the single line: cgroup_memory=1 cgroup_enable=memory
sudo reboot
```

### `kubectl` returns "connection refused"

The cluster may still be starting — the podman machine boots first
(~30 s), then minikube pulls and starts the node image (several minutes
on first boot). Check the service:

```bash
sudo -u baize env XDG_RUNTIME_DIR=/run/user/$(id -u baize) \
    journalctl --user -u minikube --since "5 minutes ago"
```

Allow up to 10 minutes on first boot.

### `sudo -u baize minikube` fails with XDG_RUNTIME_DIR error

`sudo -u baize` (unlike `runuser -l`) does NOT create a login session,
so `XDG_RUNTIME_DIR` is never set — always prefix commands with
`env XDG_RUNTIME_DIR=/run/user/$(id -u baize)` (and, for podman/minikube,
`CONTAINER_HOST=unix:///run/user/$(id -u baize)/podman/minikube-api.sock`),
or use the `bk` wrapper function documented in
[06-operations.md](06-operations.md).

If the runtime directory itself is missing even with the env var set,
check that lingering is enabled:

```bash
loginctl show-user baize | grep Linger
# Expected: Linger=yes
```

If not:

```bash
sudo loginctl enable-linger baize
```

### Podman machine will not start / "missing virtiofsd" errors

The installer links the helper binaries (`gvproxy`, `virtiofsd`) into
`/usr/libexec/podman/` and adds `baize` to the `kvm` group (see
[03-rootless-containers.md](03-rootless-containers.md) for why). If the
links were removed, reinstall the package — the postinst re-creates
everything idempotently:

```bash
sudo apt install --reinstall baize-kube
```

### Volume already exists error on minikube start

A previous failed start left a dangling volume:

```bash
sudo -u baize env XDG_RUNTIME_DIR=/run/user/$(id -u baize) \
    CONTAINER_HOST=unix:///run/user/$(id -u baize)/podman/minikube-api.sock \
    podman volume rm minikube
sudo -u baize env XDG_RUNTIME_DIR=/run/user/$(id -u baize) \
    systemctl --user start minikube
```

### Kubeconfig is stale after cluster reconfiguration

Regenerate the admin kubeconfig with the packaged helper (it handles the
umask, permissions, and environment variables correctly):

```bash
sudo baize-kube-update-admin-kubeconfig
```

For consumer kubeconfigs, use:

```bash
sudo baize-kube-update-kubeconfig <username>
```

---

## Uninstallation

```bash
sudo dpkg -r baize-kube
```

This will:

- Stop and delete the minikube cluster
- Disable systemd lingering for baize
- Remove the `baize` user and home directory
- Remove the `baize-admins` and `baize-consumers` groups
- Preserve `/etc/baize-kube/consumers.conf` (purge deletes it)
- Remove management scripts from `/usr/bin/`
- Remove `/usr/local/bin/minikube` and `/usr/local/bin/kubectl`
- Remove the cgroup delegation config
- Remove the shell profile snippet
- Remove the post-reboot trigger service and flag file

**Reinstall note:** `consumers.conf` is preserved and re-adopted
automatically, but consumer kubeconfigs are NOT — after remove+reinstall,
re-run `sudo baize-kube-add-consumer <username>` for each user.

**What is NOT removed:** The `cgroup_memory=1 cgroup_enable=memory` parameters in `/boot/firmware/cmdline.txt`. These are harmless on their own but can be removed manually if desired:

```bash
sudo nano /boot/firmware/cmdline.txt
# Remove: cgroup_memory=1 cgroup_enable=memory
sudo reboot
```

A backup of the original `cmdline.txt` is at `/boot/firmware/cmdline.txt.bak-baize-kube`.
