# 06 — Operations Guide

## Installation

```bash
sudo dpkg -i baize-kube_<version>_arm64.deb
```

If the cgroup memory controller is not yet active, the installer will patch `/boot/firmware/cmdline.txt`, exit with code 1 (leaving the package in "Half-Configured" state), and display instructions to reboot:

```bash
sudo reboot
```

On the next boot, a oneshot systemd service (`baize-kube-reboot.service`) runs automatically and completes the installation — downloading binaries, provisioning the `baize` user, starting the cluster, and writing the admin kubeconfig. No manual re-run of `dpkg -i` is needed.

**Check that the automatic completion succeeded:**

```bash
systemctl status baize-kube-reboot
# A successful run shows "Active: inactive (dead)" with no errors.
# Use journalctl -u baize-kube-reboot for full logs.
```

If the cgroup controller was already active, the installer completes fully in a single pass.

---

## Verifying the installation

**Check cgroup controllers are active:**
```bash
cat /sys/fs/cgroup/cgroup.controllers
# Expected: cpuset cpu io memory pids
```

**Check the podman machine (the cluster node runs inside it):**
```bash
sudo -u baize env XDG_RUNTIME_DIR=/run/user/$(id -u baize) podman machine ls
# Expected: machine "minikube" in state "Running"
```

**Check baize user service is running:**
```bash
sudo -u baize env XDG_RUNTIME_DIR=/run/user/$(id -u baize) systemctl --user status minikube
```

**Check the cluster is up (as a consumer):**
```bash
kubectl get nodes
# Expected: minikube   Ready   ...
```

**Check kubeconfig is accessible:**

For admins (members of `baize-admins`):
```bash
echo $KUBECONFIG
# Expected: /etc/baize-kube/admin-kubeconfig
# (set automatically on login via /etc/profile.d/baize-kube.sh)
```

For consumers (provisioned via `baize-kube-add-consumer`):
```bash
kubectl get nodes
# Uses ~/.kube/config (600, user-owned), provisioned per-user
```

If KUBECONFIG is not set for an admin, log out and back in, or source it manually:
```bash
export KUBECONFIG=/etc/baize-kube/admin-kubeconfig
```

---

## Daily operations (as a consumer)

### Check cluster status
```bash
kubectl get nodes
kubectl get pods --all-namespaces
```

### Check minikube service logs
```bash
sudo -u baize env XDG_RUNTIME_DIR=/run/user/$(id -u baize) journalctl --user -u minikube -f
```

### Check minikube status
```bash
sudo -u baize env XDG_RUNTIME_DIR=/run/user/$(id -u baize) minikube status
```

---

## Cluster administration (as an admin via sudo)

All minikube reconfiguration must be done as `baize`, with its runtime
environment (`XDG_RUNTIME_DIR` and `CONTAINER_HOST` — the latter points
at the podman machine's API socket). Typing both every time is tedious,
so define a wrapper function in your shell first:

```bash
bk() { sudo -u baize env \
    XDG_RUNTIME_DIR=/run/user/$(id -u baize) \
    CONTAINER_HOST=unix:///run/user/$(id -u baize)/podman/minikube-api.sock \
    "$@"; }
```

(`baize-kube-help` section 5 documents this too. The `sudo -u baize`
pattern preserves audit logging; everything below assumes the `bk`
function is defined.)

### Enable a minikube addon
```bash
bk minikube addons enable ingress
```

### Change resource allocation

minikube REFUSES memory/CPU changes for an existing cluster ("You cannot
change the memory size for an existing minikube cluster. Please first
delete the cluster."). The sizes involved live on two layers:

- the **podman machine** (fixed at install via `BAIZE_KUBE_MACHINE_*`)
- the **node container inside the machine** (minikube's `--memory`, which
  must stay ~1 GiB BELOW the machine size to leave room for the guest OS)

To resize the machine: remove + reinstall with different
`BAIZE_KUBE_MACHINE_*` values (the machine is re-created):

```bash
sudo dpkg -r baize-kube
sudo env BAIZE_KUBE_MACHINE_CPUS=2 BAIZE_KUBE_MACHINE_MEMORY=6144 \
    dpkg -i baize-kube_<version>_arm64.deb
```

To resize only the node container (machine unchanged):

```bash
bk minikube delete
bk minikube start --memory=4096 --cpus=2
```

Never set the node memory within ~1 GiB of the machine size — the guest
OS would be starved and the node OOM-killed.

### Access minikube dashboard
```bash
bk minikube dashboard --url
# Then open the URL in a browser as the consumer
```

### View minikube config
```bash
bk minikube config view
```

### Restart the cluster manually
```bash
bk systemctl --user restart minikube
```

---

## Adding a new consumer user

To give another user on the system access to the cluster:

1. Add the user to the consumers group:
   ```bash
   sudo usermod -aG baize-consumers <username>
   ```

2. Provision per-user kubeconfig access:
   ```bash
   sudo baize-kube-add-consumer <username> [--role view]
   ```
   This creates a dedicated ServiceAccount and writes a per-user kubeconfig to `~<username>/.kube/config` (mode 600, user-owned). The `--role` flag defaults to `view`; use `--role edit` for write access.

3. The user must log out and back in for the group change to take effect. Their kubeconfig is ready immediately after step 2.

---

## Updating minikube and kubectl

The package pins both versions AND their SHA256 hashes in its postinst
(minikube to the GitHub release, kubectl to dl.k8s.io) and refuses to
install a binary that does not match the pin. Because of that, manual
`curl` updates are actively harmful: an unpinned binary would make the
next `dpkg --configure`/reinstall FAIL the hash check, and "latest"
versions would break the deliberate kubectl↔cluster version skew
(kubectl must match the cluster's minor version).

**The supported update procedure is:**

1. Bump `MINIKUBE_VERSION`, `MINIKUBE_SHA256`, `KUBECTL_VERSION`, and
   `KUBECTL_SHA256` in the postinst (each hash is published alongside
   the release: minikube's in the GitHub release notes/`.sha256` asset,
   kubectl's at `https://dl.k8s.io/release/<version>/bin/linux/arm64/kubectl.sha256`).
   ALSO update: the version-linkage comment near the pins (which minikube
   version defaults to which Kubernetes version — verify against the
   release notes), and the version-specific prose in doc/05.
2. Note: an EXISTING cluster keeps its old Kubernetes version after a
   binary-only upgrade (one minor of skew is within policy). To move the
   cluster to the new default: `bk minikube delete && bk systemctl --user
   start minikube`.
3. Rebuild and reinstall the package:

```bash
make build VERSION=<new version>
sudo dpkg -i baize-kube_<new-version>_arm64.deb
```

The installer re-hashes any installed binary against the new pins and
replaces it when they differ (the cluster keeps running throughout).

> **Offline note:** `minikube kubectl ...` (used by the admin-kubeconfig
> regeneration paths) does NOT use the pinned /usr/local/bin/kubectl —
> it downloads its own copy, keyed to the cluster's version, into
> `~baize/.minikube/cache/`. First-time regeneration therefore needs
> network access even though kubectl is installed on disk.

---

## Troubleshooting

### `kubectl` returns "connection refused"

The cluster may still be starting — the podman machine boots first
(~30 s), then minikube pulls and starts the node image (several minutes
on first boot). Check the service:
```bash
sudo -u baize env XDG_RUNTIME_DIR=/run/user/$(id -u baize) \
    journalctl --user -u minikube --since "5 minutes ago"
```

Allow up to 10 minutes on first boot.

### cgroup memory controller not active after reboot

Verify the cmdline.txt patch was applied:
```bash
cat /boot/firmware/cmdline.txt | grep -o 'cgroup_enable=memory'
```

If absent, apply manually:
```bash
sudo nano /boot/firmware/cmdline.txt
# Add to end of the single line: cgroup_memory=1 cgroup_enable=memory
sudo reboot
```

### `sudo -u baize minikube` fails with XDG_RUNTIME_DIR error

`sudo -u baize` (unlike `runuser -l`) does NOT create a login session, so
`XDG_RUNTIME_DIR` is never set. That is why every example in this
document uses the `bk` wrapper (or `sudo -u baize env XDG_RUNTIME_DIR=...`)
— plain `sudo -u baize minikube ...` will not work.

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
`/usr/libexec/podman/` and adds `baize` to the `kvm` group. If podman was
upgraded or the links were removed, verify:
```bash
ls -l /usr/libexec/podman/   # gvproxy and virtiofsd symlinks must exist
ls -l /dev/kvm               # must be accessible by group kvm
id baize                      # must list kvm in the groups
```

If anything is missing, reinstall the package (the postinst re-creates
all of it idempotently):
```bash
sudo apt install --reinstall baize-kube
```

### Volume already exists error on minikube start

A previous failed start left a dangling volume:
```bash
bk podman volume rm minikube
bk systemctl --user start minikube
```

### Kubeconfig is stale after cluster recreation

The admin kubeconfig is a SNAPSHOT: its server endpoint is
`https://127.0.0.1:<port>` where the port is a random host port assigned by
the podman machine's port-forwarding. Whenever the minikube container is
recreated (delete/start), that port CHANGES and every admin kubeconfig goes
stale ("connection refused"), while `bk minikube status` still shows a
healthy cluster. Consumer kubeconfigs keep working (their ServiceAccount
tokens are unaffected) but their server endpoint must also be refreshed.

Regenerate the admin kubeconfig:
```bash
sudo baize-kube-update-admin-kubeconfig
```

Then refresh each consumer kubeconfig:
```bash
sudo baize-kube-update-kubeconfig <username>
```

**Note on the endpoint:** the API server is reachable at `127.0.0.1` —
LOCAL to the Pi. Admins on other machines must use an SSH tunnel
(`ssh -L 6443:127.0.0.1:<port> pi`) or run kubectl on the Pi itself.

---

## Uninstallation

### Plain remove (cluster destroyed, config preserved)

```bash
sudo dpkg -r baize-kube
```

This will:
- Stop and delete the minikube cluster (and stop/remove the podman machine)
- Disable systemd lingering for baize
- Remove the `baize` user and home directory
- Remove the `baize-consumers` and `baize-admins` groups
- Remove every consumer kubeconfig (their bearer tokens die with the cluster)
- Remove the admin kubeconfig credential file
- Remove `/usr/local/bin/minikube` and `/usr/local/bin/kubectl`
- Remove the cgroup delegation config and the shell profile snippet

**Preserved for reinstall:** `/etc/baize-kube/consumers.conf` (your
admin-authored consumer list) — postinst re-adopts it automatically on
reinstall. Note that consumer kubeconfigs are NOT restored automatically:
after a remove+reinstall, re-run `sudo baize-kube-add-consumer <username>`
for each user.

### Purge (everything, including the preserved config)

```bash
sudo dpkg --purge baize-kube
```

Additionally deletes `/etc/baize-kube/` (consumers.conf) and the debconf
answers. Run this when you want no baize-kube state left on the machine.

**What is NOT removed:** The `cgroup_memory=1 cgroup_enable=memory` parameters in `/boot/firmware/cmdline.txt`. These are harmless on their own but can be removed manually if desired:

```bash
sudo nano /boot/firmware/cmdline.txt
# Remove: cgroup_memory=1 cgroup_enable=memory
sudo reboot
```

A backup of the original `cmdline.txt` is at `/boot/firmware/cmdline.txt.bak-baize-kube`.
