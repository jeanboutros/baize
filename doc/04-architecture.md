# 04 — Package Architecture

## Overview

`baize-kube` provisions a self-contained, rootless Kubernetes cluster on a Raspberry Pi. The cluster is owned by a dedicated service account and is available to human users without requiring them to have any special privileges beyond group membership.

## Components

```
┌─────────────────────────────────────────────────────────────┐
│  Raspberry Pi 5 (arm64, Raspberry Pi OS Bookworm)           │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  systemd (PID 1)                                     │  │
│  │                                                      │  │
│  │  user@<baize-uid>.service  (lingering, starts boot)  │  │
│  │    └── minikube.service                              │  │
│  │          └── minikube start --driver=podman          │  │
│  │                └── podman (rootless)                 │  │
│  │                      └── minikube container          │  │
│  │                            └── Kubernetes control    │  │
│  │                                plane + kubelet       │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────┐    ┌─────────────────────────────────┐   │
│  │  baize user  │    │  baize-consumers group           │   │
│  │  (locked)    │    │  ├── huyang                     │   │
│  │              │    │  └── (any other human users)    │   │
│  └──────────────┘    └─────────────────────────────────┘   │
│                                        │                    │
│                          /etc/baize-kube/kubeconfig         │
│                          (group-readable, 640)              │
│                                        │                    │
│                          /etc/profile.d/baize-kube.sh       │
│                          (auto-sets KUBECONFIG on login)    │
└─────────────────────────────────────────────────────────────┘
```

## File layout

| Path | Purpose |
|---|---|
| `/home/baize/` | baize user home; holds `.kube/`, `.minikube/`, `.config/` |
| `/home/baize/.config/systemd/user/minikube.service` | User service unit |
| `/etc/baize-kube/kubeconfig` | Shared, group-readable kubeconfig |
| `/etc/profile.d/baize-kube.sh` | Sets KUBECONFIG automatically for consumers |
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
6. `huyang` logs in; `/etc/profile.d/baize-kube.sh` sets `KUBECONFIG=/etc/baize-kube/kubeconfig`
7. `huyang` runs `kubectl get nodes` — works immediately

## Security boundaries

| Boundary | Mechanism |
|---|---|
| baize cannot log in interactively | shell set to `/usr/sbin/nologin`, password locked |
| baize containers cannot escalate to host root | rootless user namespace, subuid/subgid mapping |
| baize cannot access other users' files | standard Unix permissions |
| huyang cannot modify cluster config | kubeconfig is read-only for consumers (640 permissions) |
| huyang can reconfigure minikube | `sudo -u baize minikube <command>` (requires sudo) |
| Consumers cannot read each other's files | group membership, not world-readable |
