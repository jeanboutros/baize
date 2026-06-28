# 06 — Operations Guide

## Installation

```bash
sudo dpkg -i baize-kube_1.0_arm64.deb
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

**Check baize user service is running:**
```bash
sudo -u baize systemctl --user status minikube
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
sudo -u baize journalctl --user -u minikube -f
```

### Check minikube status
```bash
sudo -u baize minikube status
```

---

## Cluster administration (as an admin via sudo)

All minikube reconfiguration must be done as `baize`. The `sudo -u baize` pattern preserves audit logging.

### Enable a minikube addon
```bash
sudo -u baize minikube addons enable ingress
```

### Change resource allocation
```bash
sudo -u baize minikube stop
sudo -u baize minikube config set memory 6000
sudo -u baize minikube config set cpus 3
sudo -u baize minikube start
```

### Access minikube dashboard
```bash
sudo -u baize minikube dashboard --url
# Then open the URL in a browser as the consumer
```

### View minikube config
```bash
sudo -u baize minikube config view
```

### Restart the cluster manually
```bash
sudo -u baize systemctl --user restart minikube
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

The package does not manage binary updates automatically. To update:

```bash
# Stop the cluster first
sudo -u baize minikube stop

# Re-download minikube
sudo curl -fsSL -o /usr/local/bin/minikube \
  https://github.com/kubernetes/minikube/releases/download/latest/minikube-linux-arm64
sudo chmod +x /usr/local/bin/minikube

# Re-download kubectl
K8S_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
sudo curl -fsSL -o /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/arm64/kubectl"
sudo chmod +x /usr/local/bin/kubectl

# Restart
sudo -u baize systemctl --user start minikube
```

---

## Troubleshooting

### `kubectl` returns "connection refused"

The cluster may still be starting. Check the service:
```bash
sudo -u baize journalctl --user -u minikube --since "5 minutes ago"
```

Allow up to 5 minutes on first boot.

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

The baize user's runtime directory may not be mounted. Trigger it:
```bash
sudo machinectl shell baize@
# This starts a proper login session for baize
exit
```

Or check if lingering is enabled:
```bash
loginctl show-user baize | grep Linger
# Expected: Linger=yes
```

If not:
```bash
sudo loginctl enable-linger baize
```

### Volume already exists error on minikube start

A previous failed start left a dangling volume:
```bash
sudo -u baize podman volume rm minikube
sudo -u baize systemctl --user start minikube
```

### Kubeconfig is stale after cluster reconfiguration

Regenerate the admin kubeconfig:
```bash
sudo baize-kube-update-kubeconfig
```

This regenerates `/etc/baize-kube/admin-kubeconfig` from the current cluster state. Consumer kubeconfigs (at `~<username>/.kube/config`) are unaffected — they use per-user ServiceAccount tokens that remain valid across cluster reconfigurations.

---

## Uninstallation

```bash
sudo dpkg -r baize-kube
```

This will:
- Stop and delete the minikube cluster
- Disable systemd lingering for baize
- Remove the `baize` user and home directory
- Remove the `baize-consumers` group
- Remove the `baize-admins` group
- Remove `/etc/baize-kube/`
- Remove `/usr/local/bin/minikube` and `/usr/local/bin/kubectl`
- Remove the cgroup delegation config
- Remove the shell profile snippet

**What is NOT removed:** The `cgroup_memory=1 cgroup_enable=memory` parameters in `/boot/firmware/cmdline.txt`. These are harmless on their own but can be removed manually if desired:

```bash
sudo nano /boot/firmware/cmdline.txt
# Remove: cgroup_memory=1 cgroup_enable=memory
sudo reboot
```

A backup of the original `cmdline.txt` is at `/boot/firmware/cmdline.txt.bak-baize-kube`.
