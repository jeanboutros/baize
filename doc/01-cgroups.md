# 01 — Control Groups (cgroups)

## What is a cgroup?

A **cgroup** (control group) is a Linux kernel feature that organises processes into a named hierarchy and lets the kernel apply resource limits and accounting to each group. It is the fundamental mechanism that gives containers their resource boundaries.

Without cgroups, a container is just a set of isolated processes (via namespaces). It can see only its own filesystem and network, but nothing prevents it from consuming all the RAM or CPU on the host. cgroups are what turns isolation into containment.

## What cgroups do

When a container runtime (Podman, containerd, Docker) starts a container, it:

1. Creates a new cgroup for that container
2. Places all the container's processes into that cgroup
3. Applies controller-specific limits to the cgroup

From that point on, the kernel enforces those limits at the scheduler and memory allocator level — not in userspace, and not bypassable by the container.

## Controllers

Each resource type is managed by a separate **controller**. The ones relevant to minikube:

| Controller | What it limits |
|---|---|
| `cpu` | CPU time shares and hard quotas |
| `cpuset` | Which physical CPU cores a group may use |
| `io` | Block I/O bandwidth and operation rates |
| `memory` | RAM usage; enforces OOM kills within the group |
| `pids` | Maximum number of processes and threads |

Controllers must be explicitly enabled — both at the kernel level and at each level of the hierarchy where you want them active.

## cgroup v1 vs cgroup v2

There are two generations of the cgroup API.

**cgroup v1** (legacy): each controller is mounted separately under `/sys/fs/cgroup/memory/`, `/sys/fs/cgroup/cpu/`, etc. This fragmented structure made it very difficult to apply consistent limits across controllers for the same group of processes.

**cgroup v2** (unified): all controllers share a single hierarchy rooted at `/sys/fs/cgroup/`. A process belongs to exactly one cgroup, and all controllers apply to it together. This is the modern standard, and it is what Raspberry Pi OS Bookworm uses.

You can verify you are on v2:

```bash
stat -fc %T /sys/fs/cgroup
# should print: cgroup2fs
```

## The memory controller on Raspberry Pi

The Raspberry Pi kernel does not enable the `memory` cgroup controller by default. This is a deliberate upstream choice to reduce kernel overhead on low-memory devices. However, rootless Podman requires the memory controller to enforce per-container memory limits.

To enable it, the kernel must be told at boot time via the command line:

```
cgroup_memory=1 cgroup_enable=memory
```

These parameters are added to `/boot/firmware/cmdline.txt` by the `baize-kube` installer if they are not already present. A reboot is required for the kernel to activate the controller.

After reboot, verify:

```bash
cat /sys/fs/cgroup/cgroup.controllers
# should include: memory
```

## Further reading

- [kernel.org cgroup v2 documentation](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)
- [Podman rootless cgroup requirements](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
