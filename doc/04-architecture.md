# 04 — Package Architecture

## Overview

`baize-kube` provisions a self-contained, rootless Kubernetes cluster on a Raspberry Pi. The cluster is owned by a dedicated service account and is available to human users through a two-group RBAC model: `baize-admins` for cluster administrators and `baize-consumers` for per-user provisioned access.

## Components

```
┌──────────────────────────────────────────────────────────────────┐
│  Raspberry Pi 5 (arm64, Raspberry Pi OS Bookworm)                │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  systemd (PID 1)                                          │  │
│  │                                                           │  │
│  │  user@<baize-uid>.service  (lingering, starts at boot)    │  │
│  │    └── minikube.service                                   │  │
│  │          ├── ExecStartPre: podman machine start minikube   │  │
│  │          └── minikube start --driver=podman                │  │
│  │                └── podman (rootless, via CONTAINER_HOST    │  │
│  │                      socket → podman machine "minikube")   │  │
│  │                      ┌─ inside the QEMU machine VM ─────┐  │  │
│  │                      │  minikube container              │  │  │
│  │                      │    └── Kubernetes control        │  │  │
│  │                      │        plane + kubelet           │  │  │
│  │                      │        (containerd runtime)      │  │  │
│  │                      └───────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  podman machine "minikube" (QEMU, KVM-accelerated)       │   │
│  │  owned by baize: 4 CPU / 6144 MB / 30 GB disk            │   │
│  │  helpers: /usr/libexec/podman/{gvproxy, virtiofsd}        │   │
│  │  API socket: /run/user/<uid>/podman/minikube-api.sock     │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────┐    ┌──────────────────────────────────┐   │
│  │  baize user      │    │  baize-admins group              │   │
│  │  (locked, kvm    │    │  ├── admin-user                  │   │
│  │  group for QEMU) │    │  └── (full cluster admin)        │   │
│  │                  │    │                                  │   │
│  └──────────────────┘    │  /etc/baize-kube/admin-kubeconfig │   │
│                          │  (group-readable, 640)           │   │
│                          └──────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  baize-consumers group                                   │   │
│  │  ├── alice  → ~alice/.kube/config  (600, per-user)      │   │
│  │  ├── bob    → ~bob/.kube/config    (600, per-user)      │   │
│  │  └── carol  → ~carol/.kube/config  (600, per-user)      │   │
│  │                                                          │   │
│  │  Each consumer gets their own ServiceAccount, token,     │   │
│  │  and RBAC bindings via baize-kube-add-consumer.          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Management scripts (/usr/bin/)                          │   │
│  │  ├── baize-kube-add-consumer                             │   │
│  │  ├── baize-kube-remove-consumer                           │   │
│  │  ├── baize-kube-list-consumers                            │   │
│  │  ├── baize-kube-update-kubeconfig                         │   │
│  │  └── baize-kube-help (interactive user guide)             │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  /etc/profile.d/baize-kube.sh                                   │
│  (auto-sets KUBECONFIG for baize-admins on login)               │
│  /etc/bash_completion.d/{minikube,kubectl}                       │
│  (shell tab-completion, regenerated at install time)            │
└──────────────────────────────────────────────────────────────────┘
```

## File layout

| Path | Purpose |
|---|---|
| `/home/baize/` | baize user home; holds `.kube/`, `.minikube/`, `.config/` |
| `/home/baize/.config/systemd/user/minikube.service` | User service unit |
| `/home/baize/.local/share/containers/` | podman machine disk image and container storage |
| `/run/user/<baize-uid>/podman/minikube-api.sock` | podman machine API socket (referenced by `CONTAINER_HOST`) |
| `/usr/libexec/podman/{gvproxy,virtiofsd}` | symlinks to Debian's podman machine helper binaries |
| `/etc/bash_completion.d/{minikube,kubectl}` | generated bash completions |
| `/etc/baize-kube/admin-kubeconfig` | Admin kubeconfig, group-readable by `baize-admins` |
| `~<username>/.kube/config` | Per-user consumer kubeconfig (600, user-owned) |
| `/etc/profile.d/baize-kube.sh` | Sets KUBECONFIG automatically for admins |
| `/usr/bin/baize-kube-add-consumer` | Provision a consumer with per-user RBAC |
| `/usr/bin/baize-kube-remove-consumer` | Deprovision a consumer |
| `/usr/bin/baize-kube-list-consumers` | List provisioned consumers |
| `/usr/bin/baize-kube-update-kubeconfig` | Regenerate a consumer's kubeconfig |
| `/usr/bin/baize-kube-update-admin-kubeconfig` | Regenerate the shared admin kubeconfig (stale-port fix) |
| `/usr/bin/baize-kube-help` | Interactive guide: users, troubleshooting, internals |
| `/etc/systemd/system/user@.service.d/delegate.conf` | cgroup delegation for all user sessions |
| `/boot/firmware/cmdline.txt` | Kernel boot parameters (patched to add memory cgroup) |
| `/usr/local/bin/minikube` | minikube binary (downloaded at install time) |
| `/usr/local/bin/kubectl` | kubectl binary (downloaded at install time) |
| `/usr/share/doc/baize-kube/` | This documentation |

## Boot sequence

1. Kernel boots with `cgroup_memory=1 cgroup_enable=memory` active
2. systemd starts and reads `/etc/systemd/system/user@.service.d/delegate.conf`, enabling cgroup delegation for all user slices
3. Because `baize` has lingering enabled, systemd starts `user@<uid>.service` for `baize` without any login
4. `user@<uid>.service` starts `minikube.service` (because it is enabled in `WantedBy=default.target`)
5. `ExecStartPre` starts the podman machine (`podman machine start minikube` — it exits non-zero (125) when already running or missing, and the unit's leading `-` makes that non-fatal while still starting a stopped machine). The QEMU VM boots with KVM acceleration (~30 s cold start)
6. `ExecStart` runs `minikube start --driver=podman --container-runtime=containerd`; minikube talks to podman via `CONTAINER_HOST`, creates the node container inside the machine, and Kubernetes starts (the first boot also pulls the node image — several minutes)
7. An admin logs in; `/etc/profile.d/baize-kube.sh` sets `KUBECONFIG=/etc/baize-kube/admin-kubeconfig`
8. The admin runs `kubectl get nodes` — works immediately
9. Consumers are provisioned on-demand with `sudo baize-kube-add-consumer <username>`

## Security boundaries

| Boundary | Mechanism |
|---|---|
| baize cannot log in interactively | shell set to `/usr/sbin/nologin`, password locked |
| baize containers cannot escalate to host root | rootless user namespace, subuid/subgid mapping |
| baize cannot access other users' files | standard Unix permissions |
| Admins have full cluster access | membership in `baize-admins` group, admin kubeconfig at `/etc/baize-kube/admin-kubeconfig` |
| Consumers have per-user RBAC | each consumer gets their own ServiceAccount, token, and kubeconfig at `~/.kube/config` (600) |
| Consumer tokens are isolated | filesystem permissions prevent cross-user token reading |
| Admins can reconfigure minikube | `sudo -u baize minikube <command>` (requires sudo, auditable) |
| Consumer provisioning requires root | `baize-kube-add-consumer` must run as root to write to other users' home directories |
