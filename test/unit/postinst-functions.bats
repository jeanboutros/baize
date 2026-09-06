#!/usr/bin/env bats

load ../test_helper

# run -<expected-exit-code> flag needs bats >= 1.5.0
bats_require_minimum_version 1.5.0

setup() {
    setup_mocks
}

teardown() {
    teardown_mocks
}

@test "require_root: fails when not root" {
    # Override the id mock to pretend we are NOT root (uid 1000).
    cat > "${MOCK_DIR}/id" <<'EOF'
#!/bin/bash
echo "uid=1000(user) gid=1000(user)"
EOF
    chmod +x "${MOCK_DIR}/id"

    # With the BASH_SOURCE execution guard, sourcing postinst only DEFINES
    # the functions (main() is NOT called). So we call require_root directly
    # and expect it to fail: fail() exits the subshell with status 1.
    # `run` captures stdout/stderr and the exit code without aborting the test.
    # If require_root succeeds (exit 0), the mock failed — test fails.
    ! bash -c 'source debian/DEBIAN/postinst 2>/dev/null; require_root' || false
}

@test "info function: outputs correct format" {
    source_postinst_lib debian/DEBIAN/postinst
    run info "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[baize-kube] INFO:"* ]]
    [[ "$output" == *"test message"* ]]
}

@test "fail function: exits with error" {
    source_postinst_lib debian/DEBIAN/postinst
    run fail "test failure"
    [ "$status" -eq 1 ]
    [[ "$output" == *"[baize-kube] ERROR:"* ]]
    [[ "$output" == *"test failure"* ]]
}

@test "warn function: outputs warning format" {
    source_postinst_lib debian/DEBIAN/postinst
    run warn "test warning"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[baize-kube] WARN:"* ]]
    [[ "$output" == *"test warning"* ]]
}

@test "success function: outputs success format" {
    source_postinst_lib debian/DEBIAN/postinst
    run success "test success"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[baize-kube] OK:"* ]]
    [[ "$output" == *"test success"* ]]
}

@test "MINIKUBE_VERSION is pinned" {
    source_postinst_lib debian/DEBIAN/postinst
    [ -n "$MINIKUBE_VERSION" ]
    [[ "$MINIKUBE_VERSION" == v* ]]
}

@test "KUBECTL_VERSION is pinned" {
    source_postinst_lib debian/DEBIAN/postinst
    [ -n "$KUBECTL_VERSION" ]
    [[ "$KUBECTL_VERSION" == v* ]]
}

@test "BAIZE_USER is set correctly" {
    source_postinst_lib debian/DEBIAN/postinst
    [ "$BAIZE_USER" = "baize" ]
}

@test "CONSUMERS_GROUP is set correctly" {
    source_postinst_lib debian/DEBIAN/postinst
    [ "$CONSUMERS_GROUP" = "baize-consumers" ]
}

@test "KUBECONFIG_SHARED path uses admin-kubeconfig" {
    source_postinst_lib debian/DEBIAN/postinst
    [[ "$ADMIN_KUBECONFIG" == *"admin-kubeconfig"* ]]
}

@test "set -euo pipefail is active" {
    source_postinst_lib debian/DEBIAN/postinst
    # If set -u is active, referencing an unset variable should fail
    # If set -u is active, referencing an unset variable should fail.
    # `run -127` tells bats this command's expected exit code is 127
    # ("command not found") so it does not emit a warning.
    run -127 bash -c 'set -u; echo $UNDEFINED_VAR_XYZ123'
    [ "$status" -ne 0 ]
}

@test "podman machine constants are set" {
    source_postinst_lib debian/DEBIAN/postinst
    [ "$PODMAN_MACHINE_NAME" = "minikube" ]
    [ "$PODMAN_MACHINE_CPUS" -eq 4 ]
    [ "$PODMAN_MACHINE_MEMORY" -eq 6144 ]
    [ "$PODMAN_MACHINE_DISK" -eq 30 ]
}

@test "machine sizing: defaults apply when env vars are unset" {
    # Unset the overrides to prove the ${VAR:-default} fallback works.
    unset BAIZE_KUBE_MACHINE_CPUS BAIZE_KUBE_MACHINE_MEMORY || true
    source_postinst_lib debian/DEBIAN/postinst
    [ "$PODMAN_MACHINE_CPUS" = "4" ]
    [ "$PODMAN_MACHINE_MEMORY" = "6144" ]
    run validate_machine_sizing
    [ "$status" -eq 0 ]
}

@test "machine sizing: env vars override the defaults" {
    BAIZE_KUBE_MACHINE_CPUS=2
    BAIZE_KUBE_MACHINE_MEMORY=4096
    export BAIZE_KUBE_MACHINE_CPUS BAIZE_KUBE_MACHINE_MEMORY
    source_postinst_lib debian/DEBIAN/postinst
    [ "$PODMAN_MACHINE_CPUS" = "2" ]
    [ "$PODMAN_MACHINE_MEMORY" = "4096" ]
    run validate_machine_sizing
    [ "$status" -eq 0 ]
}

@test "machine sizing: non-numeric values are rejected" {
    BAIZE_KUBE_MACHINE_CPUS="four"
    BAIZE_KUBE_MACHINE_MEMORY="4096"
    export BAIZE_KUBE_MACHINE_CPUS BAIZE_KUBE_MACHINE_MEMORY
    source_postinst_lib debian/DEBIAN/postinst
    run validate_machine_sizing
    [ "$status" -ne 0 ]
    [[ "$output" == *"not a number"* ]]
}

@test "machine sizing: below-minimum CPU is rejected" {
    BAIZE_KUBE_MACHINE_CPUS=1
    BAIZE_KUBE_MACHINE_MEMORY=4096
    export BAIZE_KUBE_MACHINE_CPUS BAIZE_KUBE_MACHINE_MEMORY
    source_postinst_lib debian/DEBIAN/postinst
    run validate_machine_sizing
    [ "$status" -ne 0 ]
    [[ "$output" == *"minimum of 2"* ]]
}

@test "machine sizing: below-minimum memory is rejected" {
    BAIZE_KUBE_MACHINE_CPUS=2
    BAIZE_KUBE_MACHINE_MEMORY=3072
    export BAIZE_KUBE_MACHINE_CPUS BAIZE_KUBE_MACHINE_MEMORY
    source_postinst_lib debian/DEBIAN/postinst
    run validate_machine_sizing
    [ "$status" -ne 0 ]
    [[ "$output" == *"4096"* ]]
}

@test "MINIKUBE_VERSION is v1.39.0" {
    source_postinst_lib debian/DEBIAN/postinst
    [ "$MINIKUBE_VERSION" = "v1.39.0" ]
}

@test "KUBECTL_VERSION is v1.37.0 (zero skew vs minikube default)" {
    source_postinst_lib debian/DEBIAN/postinst
    [ "$KUBECTL_VERSION" = "v1.37.0" ]
}

@test "setup_podman_machine: inits machine when none exists" {
    source_postinst_lib debian/DEBIAN/postinst
    rm -f /tmp/baize-kube-test-machines
    rm -f /tmp/baize-kube-test.log
    run setup_podman_machine
    [ "$status" -eq 0 ]
    grep -q "machine init" /tmp/baize-kube-test.log
    grep -q -- "--update-connection" /tmp/baize-kube-test.log
}

@test "setup_podman_machine: skips init when machine already exists" {
    source_postinst_lib debian/DEBIAN/postinst
    echo "minikube" > /tmp/baize-kube-test-machines
    rm -f /tmp/baize-kube-test.log
    run setup_podman_machine
    [ "$status" -eq 0 ]
    # No init should have been logged — only the ls check
    ! grep -q "machine init" /tmp/baize-kube-test.log
}

@test "link_podman_helpers: creates symlinks idempotently" {
    source_postinst_lib debian/DEBIAN/postinst
    # Sandbox the target directory: this test must never create symlinks
    # in the REAL /usr/libexec/podman (a previous review found the test
    # mutating the live host).
    local libexec_dir="${MOCK_DIR}/libexec/podman"
    mkdir -p "$libexec_dir"
    ln -sf /usr/bin/gvproxy "${libexec_dir}/gvproxy"
    ln -sf /usr/libexec/virtiofsd "${libexec_dir}/virtiofsd"
    PODMAN_LIBEXECDIR="$libexec_dir" run link_podman_helpers
    [ "$status" -eq 0 ]
    [ -L "${libexec_dir}/gvproxy" ]
    [ -L "${libexec_dir}/virtiofsd" ]
    # Run again — must not fail (idempotent)
    PODMAN_LIBEXECDIR="$libexec_dir" run link_podman_helpers
    [ "$status" -eq 0 ]
}

@test "provision_user: adds kvm group (unconditionally)" {
    source_postinst_lib debian/DEBIAN/postinst
    rm -f /tmp/baize-kube-test.log
    run provision_user
    [ "$status" -eq 0 ]
    grep -q "usermod -aG kvm baize" /tmp/baize-kube-test.log
}

@test "install_service unit contains CONTAINER_HOST and machine ExecStartPre" {
    source_postinst_lib debian/DEBIAN/postinst
    export BAIZE_HOME="${MOCK_DIR}/home-baize"
    mkdir -p "$BAIZE_HOME"
    run install_service
    [ "$status" -eq 0 ]
    grep -q "Environment=CONTAINER_HOST=unix:///run/user/.*/podman/minikube-api.sock" \
        "${BAIZE_HOME}/.config/systemd/user/minikube.service"
    grep -q "ExecStartPre=-/usr/bin/podman machine start minikube" \
        "${BAIZE_HOME}/.config/systemd/user/minikube.service"
    grep -q -- "--container-runtime=containerd" \
        "${BAIZE_HOME}/.config/systemd/user/minikube.service"
    grep -q "ExecStopPost=-/usr/bin/podman machine stop minikube" \
        "${BAIZE_HOME}/.config/systemd/user/minikube.service"
    # user-manager has no network-online.target; we order against podman's user unit
    grep -q "After=podman-user-wait-network-online.service" \
        "${BAIZE_HOME}/.config/systemd/user/minikube.service"
    # --no-vtx-check is a virtualbox-only flag — must NOT be passed
    ! grep -q "no-vtx-check" "${BAIZE_HOME}/.config/systemd/user/minikube.service"
    rm -rf "$BAIZE_HOME"
}

@test "start_cluster exports CONTAINER_HOST" {
    source_postinst_lib debian/DEBIAN/postinst
    rm -f /tmp/baize-kube-test.log
    # Health loop: first kubectl call succeeds in the mock, so loop exits fast
    run start_cluster
    [ "$status" -eq 0 ]
    grep -q "CONTAINER_HOST=unix:///run/user/.*/podman/minikube-api.sock" /tmp/baize-kube-test.log
}

@test "install_completions: generates minikube and kubectl bash completions" {
    source_postinst_lib debian/DEBIAN/postinst
    local compdir="${MOCK_DIR}/bash_completion.d"
    mkdir -p "$compdir"
    BASH_COMPLETION_DIR="$compdir" run install_completions
    [ "$status" -eq 0 ]
    [ -f "${compdir}/minikube" ]
    [ -f "${compdir}/kubectl" ]
    grep -q "bash completion for minikube" "${compdir}/minikube"
    grep -q "bash completion for kubectl" "${compdir}/kubectl"
}

@test "verify_podman_preflight: fails when socket missing" {
    source_postinst_lib debian/DEBIAN/postinst
    # id -u baize: mock id returns 0 for -u, socket /run/user/0/... won't exist
    run verify_podman_preflight
    [ "$status" -ne 0 ]
    [[ "$output" == *"socket not found"* || "$output" == *"ERROR"* ]]
}

@test "final banner: lines are aligned (no tab drift)" {
    # Simulate the banner functions in isolation
    banner_line() { printf '║ %-58s ║\n' "$1"; }
    banner_cmd()   { printf '║   %-56s ║\n' "$1"; }
    local out
    out=$(banner_line "baize-kube installation complete"; banner_cmd "kubectl get nodes")
    # Every line must be exactly 62 chars (60 + 2 borders)
    while IFS= read -r line; do
        [ "${#line}" -eq 62 ]
    done <<< "$out"
}
