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
│  │  user@<baize-uid>.service  (lingering, starts boot)       │  │
│  │    └── minikube.service                                   │  │
│  │          └── minikube start --driver=podman               │  │
│  │                └── podman (rootless)                      │  │
│  │                      └── minikube container               │  │
│  │                            └── Kubernetes control         │  │
│  │                                plane + kubelet            │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────┐    ┌──────────────────────────────────┐   │
│  │  baize user      │    │  baize-admins group              │   │
│  │  (locked)        │    │  ├── admin-user                  │   │
│  │                  │    │  └── (full cluster admin)        │   │
│  └──────────────────┘    │                                  │   │
│                          │  /etc/baize-kube/admin-kubeconfig │   │
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
│  │  Management scripts (/usr/local/bin/)                    │   │
│  │  ├── baize-kube-add-consumer                             │   │
│  │  ├── baize-kube-remove-consumer                          │   │
│  │  ├── baize-kube-list-consumers                           │   │
│  │  └── baize-kube-update-kubeconfig                        │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  /etc/profile.d/baize-kube.sh                                   │
│  (auto-sets KUBECONFIG for baize-admins on login)               │
└──────────────────────────────────────────────────────────────────┘
```

## File layout

| Path | Purpose |
|---|---|
| `/home/baize/` | baize user home; holds `.kube/`, `.minikube/`, `.config/` |
| `/home/baize/.config/systemd/user/minikube.service` | User service unit |
| `/etc/baize-kube/admin-kubeconfig` | Admin kubeconfig, group-readable by `baize-admins` |
| `~<username>/.kube/config` | Per-user consumer kubeconfig (600, user-owned) |
| `/etc/profile.d/baize-kube.sh` | Sets KUBECONFIG automatically for admins |
| `/usr/local/bin/baize-kube-add-consumer` | Provision a consumer with per-user RBAC |
| `/usr/local/bin/baize-kube-remove-consumer` | Deprovision a consumer |
| `/usr/local/bin/baize-kube-list-consumers` | List provisioned consumers |
| `/usr/local/bin/baize-kube-update-kubeconfig` | Regenerate a consumer's kubeconfig |
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
5. minikube starts the Podman container, Kubernetes starts inside it
6. An admin logs in; `/etc/profile.d/baize-kube.sh` sets `KUBECONFIG=/etc/baize-kube/admin-kubeconfig`
7. The admin runs `kubectl get nodes` — works immediately
8. Consumers are provisioned on-demand with `sudo baize-kube-add-consumer <username>`

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
