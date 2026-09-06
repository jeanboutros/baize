# 05 — Design Decisions

Every significant choice in this package was a deliberate trade-off. This document records each decision, the alternatives considered, and the reasoning.

---

## Why a dedicated `baize` service account?

**Decision:** The cluster is owned by a locked user account `baize`, separate from any human user.

**Alternatives considered:**
- Run minikube as a consumer directly
- Run minikube as root

**Reasoning:** Running minikube as a consumer ties the cluster lifecycle to that consumer's login session. If the consumer logs out, the cluster stops. It also means the cluster's state files, credentials, and configuration live in the consumer's home directory, mixing personal and infrastructure concerns.

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

**Reasoning:** The Docker socket model (`/var/run/docker.sock`) grants root-equivalent access to anyone who can write to it. This is a well-documented privilege escalation vector and is not appropriate for a shared machine where consumers have limited privilege.

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

**Reasoning:** The `baize` account is infrastructure, not a person. No human should log in as `baize` interactively. Administrative access to the cluster is done by an administrator via `sudo -u baize`, which requires the administrator to authenticate with their own password. This preserves a full audit trail: the sudo log records who did what, as whom, and when.

An account that nobody should log into should be incapable of logging in.

---

## Why `sudo -u baize` for cluster administration, not group membership?

**Decision:** Cluster administrators use `sudo -u baize minikube <command>`.

**Alternatives considered:**
- Give a consumer write access to `baize`'s home directory
- Add a consumer to the `baize` group with write permissions on `.minikube/`

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

**Decision:** The installer exits with code **1** after patching `cmdline.txt`, leaving the package in "Half-Configured" state. A oneshot systemd service (`baize-kube-reboot.service`) completes the installation automatically on the next boot. No manual re-run of `dpkg -i` is required.

**Alternatives considered:**
- Warn and continue (leave system in broken state)
- Exit with code 0 and require the user to manually re-run `dpkg -i`

**Reasoning:** The memory cgroup controller cannot be activated without a reboot. If the installer continues without it, minikube will fail to start with the same error that prompted this package to be written. Leaving the system in a half-installed state is worse than stopping cleanly with clear instructions.

Exiting with code 1 and using dpkg's "Half-Configured" state is the correct Debian packaging pattern for installations that require a reboot to complete. The oneshot systemd service runs on next boot, completes the installation (downloading binaries, provisioning the `baize` user, starting the cluster), and then marks the package as fully installed via `dpkg --configure`. The service logs all output to the journal, so the user can inspect the result with `systemctl status baize-kube-reboot` or `journalctl -u baize-kube-reboot`.

This approach is transparent (the user is told to reboot and check the service), idempotent (the oneshot service is guarded by a condition file), and does not require the user to remember to re-run a command after reboot.

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

**Decision:** Two groups control cluster access with different models. `baize-admins` get a shared admin kubeconfig at `/etc/baize-kube/admin-kubeconfig`. `baize-consumers` get no automatic access — each consumer is provisioned individually via `baize-kube-add-consumer`, which creates a per-user kubeconfig at `~<username>/.kube/config` (mode 600, user-owned).

**Alternatives considered:**
- Copy the kubeconfig to each consumer's home directory (old shared-kubeconfig model)
- Make the kubeconfig world-readable
- A single shared kubeconfig for all consumers

**Reasoning:** The old model of a single shared kubeconfig for all consumers had two problems: (1) all consumers shared the same credentials, making it impossible to assign different roles (view vs. edit) to different users; (2) revoking one consumer's access required rotating credentials for everyone.

The two-group per-user RBAC model solves both. Each consumer gets a dedicated Kubernetes ServiceAccount with a per-user token. The `baize-kube-add-consumer` script creates the ServiceAccount, generates a token, and writes a kubeconfig to the user's home directory. The `--role` flag (default `view`, also `edit`) controls the RBAC role binding. Token-based auth is revocable: deleting the ServiceAccount immediately cuts off that user's access without affecting anyone else.

Filesystem isolation (mode 600, user-owned) prevents credential sharing between consumers. The admin kubeconfig at `/etc/baize-kube/admin-kubeconfig` is group-readable by `baize-admins` (mode 640) and provides cluster-admin access for administrative operations.

World-readable would expose the kubeconfig (which includes cluster credentials) to any process on the system. The group model restricts access to explicitly authorised users.

---

## Why arm64 only?

**Decision:** `Architecture: arm64` in the control file.

**Reasoning:** This package is specifically designed for the Raspberry Pi 5, which uses an arm64 (AArch64) processor. The minikube and kubectl binaries downloaded are the arm64 builds. The cgroup boot parameters and kernel assumptions are specific to the Raspberry Pi kernel. There is no tested or supported path for x86_64 or armhf.

---

## Why `--no-vtx-check` was REMOVED from minikube start

**Decision:** The flag is no longer passed to `minikube start`.

**Reasoning (corrected twice — a cautionary tale about verifying against
upstream source):** minikube v1.39.0's `start_flags.go` marks `--no-vtx-check`
as **"(virtualbox driver only)"** — the check it disables never runs for any
other driver, so the flag was a no-op in this stack the whole time. This
document previously claimed the Pi 5 "does not have KVM", which is also
wrong: `/dev/kvm` is present on Raspberry Pi OS and the podman machine uses
it for QEMU hardware acceleration (hence `baize` is added to the `kvm`
group; without KVM, QEMU falls back to TCG emulation — orders of magnitude
slower). Since the flag does nothing for the podman driver, removing it
removes cargo cult; nothing about the cluster changes.

**Verification:** upstream source, cmd/minikube/cmd/start_flags.go at tag
v1.39.0: "Disable checking for the availability of hardware virtualization
before the vm is started (virtualbox driver only)".

---

## Why a dedicated podman machine for minikube?

**Decision:** The installer creates a named podman machine (`minikube`, QEMU provider, 4 CPU / 6144 MB / 30 GB) owned by the `baize` user, and points every podman/minikube invocation at its API socket via `CONTAINER_HOST=unix:///run/user/<baize-uid>/podman/minikube-api.sock`.

**Alternatives considered:**
- Rely on host rootless podman directly (no machine)
- Expect the admin to create and wire the machine manually

**Reasoning:** On Debian, the podman machine stack does not work out of the box. Two helper binaries live outside podman's search path and must be linked into `/usr/libexec/podman/`:

| Helper | Debian path | Podman expects | Effect of absence |
|---|---|---|---|
| `virtiofsd` (package `virtiofsd`) | `/usr/libexec/virtiofsd` | `/usr/libexec/podman/virtiofsd` | `podman machine start` **fails** (not in `$PATH`, not in a helper dir) |
| `gvproxy` (package `gvproxy`) | `/usr/bin/gvproxy` | `/usr/libexec/podman/gvproxy` | found via `$PATH` only because Debian patches podman (Debian bug tracker, patch `0008-Allow-searching-the-system-PATH-for-gvproxy`); the symlink is belt-and-braces |

Without these links the machine cannot start, minikube's podman driver then talks to a broken host podman service, and the install fails deep inside `minikube start` — exactly the failure that motivated this design. The postinst therefore: installs the helper packages (`Depends:`), creates the symlinks, adds `baize` to the `kvm` group (QEMU hardware acceleration via `/dev/kvm`), creates the machine idempotently (`--update-connection` also makes it the user's default podman connection), and verifies the socket before starting minikube. The machine is stopped in `prerm` and removed in `postrm` (both remove and purge — the machine's disk image lives under the `baize` home, so it dies with the user anyway; explicit removal keeps `podman system connection` clean for reinstalled systems).

**Why the machine is stopped by `ExecStopPost` but NOT by `ExecStop`:** the unit's `ExecStop` is a bare `minikube stop` — the fast path: the cluster goes down, the machine keeps running, and the next `minikube start` skips the ~30 s VM boot entirely. `ExecStopPost=-podman machine stop minikube` is a *different* concern: whenever the UNIT stops — including `systemctl --user stop/restart` and host shutdown — systemd would otherwise SIGTERM the whole unit cgroup, and the QEMU process lives in it (podman's machine starter forks and releases QEMU into the service's cgroup). A SIGKILLed QEMU is an unclean VM poweroff, which risks guest-filesystem corruption over time. `ExecStopPost` performs a clean QMP/ACPI powerdown *before* systemd sweeps the cgroup; the machine is started again by `ExecStartPre` on the next unit start. Package removal (prerm/postrm) is a separate, explicit stop+remove path.

**Why machine sizing is overridable via environment variables:** the defaults (4 CPU / 6144 MiB / 30 GiB) suit a Pi with 8 GB of RAM (a full 8 GiB machine would overcommit the host). Installers on smaller boards need a way to shrink the machine without hand-editing the postinst. Two variables, read once at install time and validated (`BAIZE_KUBE_MACHINE_CPUS`, `BAIZE_KUBE_MACHINE_MEMORY`; enforced minimums 2 CPU and 4096 MiB — minikube's 3072 MiB suggested node allocation (verified in v1.39.0 source, suggestMemoryAllocation) plus ~1 GiB of guest-OS overhead), keep this a supported configuration surface rather than a fork of the script. A GitHub-runner install test was considered and rejected: hosted runners have no nested virtualization (`/dev/kvm`), so the QEMU machine would fall back to TCG software emulation — the cluster test would be slow and flaky, exactly the failure mode this package exists to prevent on real hardware.

---

## Why pin kubectl to the same minor version as the cluster?

**Decision:** kubectl is pinned to v1.37.0, matching the Kubernetes version that minikube v1.39.0 deploys by default.

**Reasoning:** The Kubernetes version-skew policy states kubectl may be at most one minor version older or newer than the API server. Since this package fully controls both versions, we pin them equal — zero skew. (The previous pin, v1.35.1 against a v1.37 cluster, silently violated the policy.) Both versions are verified against upstream release notes at bump time; each pinned SHA256 in the postinst is anchored to its authoritative source — minikube's to the GitHub release, kubectl's to dl.k8s.io — and verified at bump time.

---

## Why the name Bai Ze?

**Decision:** The project is named after Bai Ze (白泽; pinyin: Báizé), a creature from Chinese mythology.

**Reasoning:** The Bai Ze myth originates from the **Bai Ze Tu** (白泽图, "Diagrams of Bai Ze"), a text from the era of the Yellow Emperor (circa 2698–2598 BCE). According to the legend, Bai Ze appeared before the Yellow Emperor and described 11,520 types of supernatural creatures. The Emperor had these descriptions recorded and illustrated, creating a bestiary that served as a guide to the spirit world.

The project's role — cataloguing and managing containerised workloads on a Raspberry Pi cluster — mirrors Bai Ze's mythological function: bringing order and understanding to a complex, invisible world. Just as the Bai Ze Tu served as a guide to the spirit world, this package serves as a guide to running a rootless Kubernetes cluster on arm64 hardware.
