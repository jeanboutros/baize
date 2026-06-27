# 05 — Design Decisions

Every significant choice in this package was a deliberate trade-off. This document records each decision, the alternatives considered, and the reasoning.

---

## Why a dedicated `baize` service account?

**Decision:** The cluster is owned by a locked user account `baize`, separate from any human user.

**Alternatives considered:**
- Run minikube as `huyang` directly
- Run minikube as root

**Reasoning:** Running minikube as `huyang` ties the cluster lifecycle to `huyang`'s login session. If `huyang` logs out, the cluster stops. It also means the cluster's state files, credentials, and configuration live in `huyang`'s home directory, mixing personal and infrastructure concerns.

Running as root defeats the purpose of rootless containers entirely and introduces a privileged daemon pattern similar to the Docker socket problem.

A dedicated service account cleanly separates the cluster (infrastructure) from the human user (consumer). The cluster can start at boot regardless of who is logged in, and multiple consumers can access it without any of them being the owner.

---

## Why is `baize` a regular user, not a system user?

**Decision:** `baize` is created with `useradd` (regular user range), not `useradd --system`.

**Alternatives considered:**
- Create as a system user (UID < 1000) with `--system`

**Reasoning:** Rootless Podman requires `/etc/subuid` and `/etc/subgid` entries for the user. On most Linux distributions, `useradd` for regular users automatically creates these entries (or they are managed by `newuid`/`usermod`). System users do not receive subuid/subgid ranges by default, and many Podman codepaths explicitly check that the user is not a system user before enabling user namespace features.

Despite being a regular user by UID range, `baize` has no interactive login capability (shell is `/usr/sbin/nologin`, password is locked), so it behaves like a service account in every practical sense.

---

## Why rootless Podman and not Docker?

**Decision:** Rootless Podman with the containerd runtime.

**Alternatives considered:**
- Docker with the Docker socket (rootful)
- Rootless Docker
- nerdctl + containerd directly

**Reasoning:** The Docker socket model (`/var/run/docker.sock`) grants root-equivalent access to anyone who can write to it. This is a well-documented privilege escalation vector and is not appropriate for a shared machine where `huyang` is a consumer with limited privilege.

Rootless Podman does not require a daemon and does not use a socket owned by root. Each user's Podman instance is a peer process. This is the direction the OCI container ecosystem is moving and is the explicit recommendation of the Podman and Kubernetes projects for development clusters.

Rootless Docker exists but is more complex to configure than Podman on Debian-derived systems. Podman is a drop-in replacement for Docker CLI commands and is available in the Raspberry Pi OS Bookworm repositories.

---

## Why containerd as the in-cluster runtime?

**Decision:** `minikube config set container-runtime containerd`

**Alternatives considered:**
- Docker (in-cluster)
- CRI-O

**Reasoning:** minikube v1.39+ defaults to `containerd` for rootless mode. Using Docker as the in-cluster runtime would require a Docker daemon inside the minikube container, adding a privileged process inside an otherwise rootless environment. containerd is lighter, does not require a daemon in the same sense, and is the runtime used in production Kubernetes distributions (GKE, EKS, AKS all use containerd).

---

## Why is `baize` locked with no password?

**Decision:** `passwd -l baize` and shell `/usr/sbin/nologin`.

**Alternatives considered:**
- Set a password for `baize` for administrative access
- Allow SSH login for `baize`

**Reasoning:** The `baize` account is infrastructure, not a person. No human should log in as `baize` interactively. Administrative access to the cluster is done by `huyang` via `sudo -u baize`, which requires `huyang` to authenticate with their own password. This preserves a full audit trail: the sudo log records who did what, as whom, and when.

An account that nobody should log into should be incapable of logging in.

---

## Why `sudo -u baize` for cluster administration, not group membership?

**Decision:** Cluster administrators use `sudo -u baize minikube <command>`.

**Alternatives considered:**
- Give `huyang` write access to `baize`'s home directory
- Add `huyang` to the `baize` group with write permissions on `.minikube/`

**Reasoning:** `sudo -u baize` runs the command with exactly `baize`'s privileges — no more, no less. It is auditable via sudo logs. It does not require granting write access to `baize`'s home directory, which would be an overly broad permission.

Group-based write access to minikube state files would allow any group member to corrupt the cluster state without going through sudo. The sudo boundary is intentional: it enforces conscious privilege escalation.

---

## Why systemd lingering?

**Decision:** `loginctl enable-linger baize` so the cluster starts at boot.

**Alternatives considered:**
- A system-level service (in `/etc/systemd/system/`) running as `baize` via `User=`
- Start minikube manually after login

**Reasoning:** Lingering is the correct mechanism for unprivileged user services that must run without an active login session. A system-level service with `User=baize` would still run in the system cgroup slice, not `baize`'s user slice, which creates complications for cgroup delegation and rootless Podman (which expects to run in the user slice).

Lingering tells systemd to start and keep `baize`'s user session alive from boot, as if they were logged in. The user service then runs in the correct cgroup subtree with full delegation. This is the documented approach in both the systemd and Podman documentation.

---

## Why does the installer hard-block on a reboot if cmdline.txt is patched?

**Decision:** The installer exits with code 0 after patching `cmdline.txt`, requiring the user to reboot and re-run `dpkg -i`.

**Alternatives considered:**
- Warn and continue (leave system in broken state)
- Schedule a post-reboot script to finish installation

**Reasoning:** The memory cgroup controller cannot be activated without a reboot. If the installer continues without it, minikube will fail to start with the same error that prompted this package to be written. Leaving the system in a half-installed state is worse than stopping cleanly with clear instructions.

A post-reboot script (via `rc.local` or a one-shot systemd unit) would run with no user present to see errors. If something went wrong in the second phase, there would be no visible output and the user would have a broken system with no explanation.

Stopping and asking the user to reboot and re-run is transparent, idempotent, and puts the user in control.

---

## Why download binaries in `postinst` rather than bundling them?

**Decision:** `minikube` and `kubectl` are downloaded during `postinst`, not included in the `.deb`.

**Alternatives considered:**
- Bundle binaries in the `.deb`
- Use a package repository for minikube and kubectl

**Reasoning:** minikube and kubectl release frequently. Bundling them would mean the `.deb` is stale within weeks. Downloading the latest version at install time ensures the user always gets a current, supported release.

The installer fails hard if the download fails (no internet, rate limited, URL changed). This is intentional: a half-installed cluster is worse than a clean failure with a clear error message. The user can retry once connectivity is restored.

A proper package repository (apt source) for minikube exists but requires trusting an external GPG key and apt source, adding complexity that is out of scope for a self-contained `.deb`.

---

## Why the `baize-consumers` group for kubeconfig access?

**Decision:** A dedicated group `baize-consumers` controls who can read the shared kubeconfig.

**Alternatives considered:**
- Copy the kubeconfig to each consumer's home directory
- Make the kubeconfig world-readable

**Reasoning:** Copying to each home directory creates N copies that can go stale when the cluster is reconfigured. The group model means there is one canonical kubeconfig that is always current. Adding a new consumer is one command: `usermod -aG baize-consumers <username>`.

World-readable would expose the kubeconfig (which includes cluster credentials) to any process on the system. The group model restricts access to explicitly authorised users.

---

## Why arm64 only?

**Decision:** `Architecture: arm64` in the control file.

**Reasoning:** This package is specifically designed for the Raspberry Pi 5, which uses an arm64 (AArch64) processor. The minikube and kubectl binaries downloaded are the arm64 builds. The cgroup boot parameters and kernel assumptions are specific to the Raspberry Pi kernel. There is no tested or supported path for x86_64 or armhf.
