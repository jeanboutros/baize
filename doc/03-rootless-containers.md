# 03 — Rootless Containers

## What rootless means

A **rootless container** is a container started and owned by an unprivileged user, with no root involvement at runtime. The container runtime (in this case Podman) runs entirely within the user's own process space and user namespace. The host kernel never grants the container or the runtime any elevated privilege.

Contrast with the traditional Docker model: the Docker daemon runs as root, and every user who can talk to the Docker socket can effectively execute arbitrary commands as root on the host. This is a well-known security boundary problem — access to the Docker socket is equivalent to root.

## Why rootless is best practice

Rootless containers are the current best practice for several reasons:

**Reduced attack surface.** If a container is compromised and its process escapes the container namespace, the escaped process has only the privileges of the unprivileged user who started the container — not root.

**No privileged daemon.** There is no long-running root daemon that all users share. Each user's Podman instance is a peer process with their own privileges.

**Alignment with least-privilege.** The `baize` user only needs to run containers. It does not need to install packages, modify system files, or do anything else root can do. Rootless gives it exactly what it needs and nothing more.

**Kubernetes and OCI ecosystem alignment.** Kubernetes itself is moving toward rootless and user namespace support. Rootless Podman is the reference implementation for this direction.

## What rootless requires

Rootless containers require three things that are not present by default on a Raspberry Pi:

### 1. User namespaces

Linux user namespaces allow a process to have a different UID/GID mapping inside the namespace than on the host. Inside the container, a process may appear to be UID 0 (root). On the host, it maps to an unprivileged UID belonging to `baize`.

This mapping is configured via `/etc/subuid` and `/etc/subgid`. The installer assigns `baize` a range of 65536 subordinate UIDs and GIDs:

```
baize:100000:65536
```

This means that UIDs 0–65535 inside `baize`'s containers map to UIDs 100000–165535 on the host. No host process or file owned by `root` (UID 0) is accessible from inside.

Verify the ranges:

```bash
grep baize /etc/subuid /etc/subgid
```

### 2. cgroup memory controller and delegation

As described in [01-cgroups.md](01-cgroups.md) and [02-delegation.md](02-delegation.md), Podman needs to create cgroups for containers, and the memory controller must be active and delegated to the user's session.

Without cgroup delegation, Podman can start containers but cannot enforce memory limits on them. The minikube container startup script explicitly checks for memory controller delegation and exits with an error if it is absent — which is the error this package is designed to fix.

### 3. Podman configured for rootless

Podman must be configured to use the rootless Podman driver and containerd runtime. The installer sets this in `baize`'s minikube config:

```bash
minikube config set driver podman
minikube config set rootless true
minikube config set container-runtime containerd
```

The `containerd` runtime is required because minikube v1.39+ defaults to `containerd` for rootless mode, and using `docker` as the in-cluster runtime would reintroduce a privileged daemon.

## The XDG_RUNTIME_DIR requirement

Rootless Podman uses `XDG_RUNTIME_DIR` to locate its socket and state files. This is typically `/run/user/<uid>`. When a user service starts at boot via systemd lingering, systemd creates this directory automatically. The minikube service unit sets this explicitly to ensure it is always correct.

## Limitations of rootless

Rootless containers have a few practical limitations to be aware of:

- Binding to ports below 1024 requires additional kernel configuration (`sysctl net.ipv4.ip_unprivileged_port_start`)
- Some kernel features (e.g. `CLONE_NEWUSER` nesting depth) have limits that differ by kernel version
- Performance overhead from user namespace UID/GID remapping is small but nonzero

None of these affect a standard minikube development cluster.
