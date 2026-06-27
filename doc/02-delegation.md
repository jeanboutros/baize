# 02 — cgroup Delegation

## The problem: cgroups are owned by root

By default, the entire cgroup hierarchy is owned and managed by root. Only root can create new cgroups, assign processes to them, or change their limits. This is intentional — unrestricted cgroup manipulation would let unprivileged users bypass resource limits set by the system administrator.

However, rootless containers need to create cgroups. When `baize` runs Podman without root privileges, Podman needs to create a sub-cgroup for each container it starts, in order to enforce memory and CPU limits on that container.

This is the tension that **delegation** resolves.

## What delegation means

Delegation is the act of root explicitly granting an unprivileged user or service ownership of a subtree of the cgroup hierarchy. Once delegated, that user can freely create, modify, and delete cgroups within their subtree — but cannot touch anything outside it.

The delegated subtree is the user's own slice of the hierarchy. For `baize` with UID 1000, that slice is:

```
/sys/fs/cgroup/user.slice/user-<uid>.slice/user@<uid>.service/
```

Within this subtree, `baize` has full ownership. Podman can create container cgroups here freely. The kernel prevents `baize` from creating cgroups anywhere else.

## How systemd manages delegation

On a modern systemd system, delegation is configured per-service via the `Delegate=` directive. This tells systemd to hand ownership of a cgroup subtree to the service's user.

The `baize-kube` installer writes the following to `/etc/systemd/system/user@.service.d/delegate.conf`:

```ini
[Service]
Delegate=cpu cpuset io memory pids
```

The `user@.service` is a systemd template unit — it is instantiated once per logged-in user (or per user with lingering enabled). Placing a drop-in config here applies delegation to every user's session on the machine.

The `Delegate=` value is a list of controllers to delegate. We delegate all five controllers that minikube and Podman need.

## The delegation chain

For delegation to work end-to-end, every level of the hierarchy from the root down to the user's slice must have the controller enabled. The chain looks like this:

```
/sys/fs/cgroup/cgroup.controllers          ← kernel must list "memory" here
    └── user.slice/cgroup.subtree_control  ← systemd writes controllers here
          └── user-<uid>.slice/cgroup.subtree_control
                └── user@<uid>.service/    ← baize's delegation starts here
                      └── [Podman creates container cgroups here]
```

If any level in the chain is missing a controller, that controller cannot be used below it. The kernel boot parameter enables `memory` at the top. The `delegate.conf` file instructs systemd to propagate it all the way down to the user service level.

## Verifying delegation

After installation and reboot, verify the full chain:

```bash
# Top level — must include memory
cat /sys/fs/cgroup/cgroup.controllers

# User slice — must include memory
BAIZE_UID=$(id -u baize)
cat /sys/fs/cgroup/user.slice/user-${BAIZE_UID}.slice/cgroup.controllers
```

Both should include: `cpuset cpu io memory pids`

## Why we delegate to all users, not just baize

The `delegate.conf` drop-in applies to the `user@.service` template, which covers all users. This is intentional: it is the standard, recommended approach on systems running rootless containers. Limiting delegation to only `baize` would require a more complex per-user service override and would break if another user on the system also needs rootless containers in the future.

Delegation does not grant any additional privilege — it only allows users to manage cgroups within their own subtree, which they already implicitly own.
