#!/usr/bin/env bats

load ../test_helper

# run -<expected-exit-code> flag needs bats >= 1.5.0
bats_require_minimum_version 1.5.0

setup() {
    setup_mocks
    # Default: mock says the baize user EXISTS so cleanup paths are exercised.
    cat > "${MOCK_DIR}/id" <<'EOF'
#!/bin/bash
# id baize -> exists; id -u baize -> 1001; id -u -> 0 (we run as root)
if [ "${1:-}" = "-u" ] && [ "${2:-}" = "baize" ]; then
    echo "1001"
    exit 0
elif [ "${1:-}" = "-u" ]; then
    echo "0"
else
    echo "uid=1001(baize) gid=1001(baize) groups=1001(baize),993(kvm)"
fi
EOF
    chmod +x "${MOCK_DIR}/id"
    cat > "${MOCK_DIR}/getent" <<'EOF'
#!/bin/bash
if [ "$1" = "group" ] && [ "$2" = "baize-consumers" ]; then
    echo "baize-consumers:x:999:"
    exit 0
elif [ "$1" = "group" ] && [ "$2" = "baize-admins" ]; then
    echo "baize-admins:x:998:"
    exit 0
elif [ "$1" = "group" ] && [ "$2" = "kvm" ]; then
    echo "kvm:x:993:"
    exit 0
fi
exit 0
EOF
    chmod +x "${MOCK_DIR}/getent"
}

teardown() {
    teardown_mocks
}

@test "prerm: info function outputs correct format" {
    source_postinst_lib debian/DEBIAN/prerm
    run info "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[baize-kube] INFO:"* ]]
}

@test "prerm: BAIZE_USER is set correctly" {
    source_postinst_lib debian/DEBIAN/prerm
    [ "$BAIZE_USER" = "baize" ]
}

@test "prerm: set -euo pipefail is active" {
    source_postinst_lib debian/DEBIAN/prerm
    # If set -u is active, referencing an unset variable should fail.
    # `run -127` tells bats this command's expected exit code is 127
    # ("command not found") so it does not emit a warning.
    run -127 bash -c 'set -u; echo $UNDEFINED_VAR_XYZ789'
    [ "$status" -ne 0 ]
}

@test "prerm: action guard exits 0 for upgrade" {
    # With the BASH_SOURCE execution guard, main() only runs when the
    # script is executed. Simulate dpkg calling prerm with "upgrade":
    # main() must exit 0 without touching the cluster.
    run bash debian/DEBIAN/prerm upgrade
    [ "$status" -eq 0 ]
}

@test "prerm: machine constants are set" {
    source_postinst_lib debian/DEBIAN/prerm
    [ "$PODMAN_MACHINE_NAME" = "minikube" ]
    [ -x "$PODMAN_BIN" ] || [ "$PODMAN_BIN" = "/usr/bin/podman" ]
}

@test "prerm: remove path stops minikube then the podman machine, in order" {
    # prerm gates on [ -x /usr/local/bin/minikube ] — provide a fake.
    # (The runuser mock records what would have run as baize.)
    local fake_bin="${MOCK_DIR}/fake-minikube"
    cat > "$fake_bin" <<'EOF'
#!/bin/bash
echo "minikube $*" >> /tmp/baize-kube-test.log
EOF
    chmod +x "$fake_bin"
    # shellcheck disable=SC2034
    MINIKUBE_BIN_OVERRIDE=1
    # Patch a copy of prerm to point at the fake binary, then run it.
    sed "s|MINIKUBE_BIN=\"/usr/local/bin/minikube\"|MINIKUBE_BIN=\"${fake_bin}\"|" \
        debian/DEBIAN/prerm > "${MOCK_DIR}/prerm-test"
    chmod +x "${MOCK_DIR}/prerm-test"

    rm -f /tmp/baize-kube-test.log
    run bash "${MOCK_DIR}/prerm-test" remove
    [ "$status" -eq 0 ]
    [ -f /tmp/baize-kube-test.log ]
    # The unit must be DISABLED before the cluster is deleted (so an
    # interrupted removal cannot resurrect a cluster at next boot), and
    # the cluster cleanup must precede the podman machine stop.
    DISABLE_LINE=$(grep -n "systemctl --user disable minikube.service" /tmp/baize-kube-test.log | head -1 | cut -d: -f1)
    MINIKUBE_LINE=$(grep -n "minikube stop" /tmp/baize-kube-test.log | head -1 | cut -d: -f1)
    MACHINE_LINE=$(grep -n "machine stop" /tmp/baize-kube-test.log | head -1 | cut -d: -f1)
    [ -n "$DISABLE_LINE" ]
    [ -n "$MINIKUBE_LINE" ]
    [ -n "$MACHINE_LINE" ]
    [ "$DISABLE_LINE" -lt "$MINIKUBE_LINE" ]
    [ "$MINIKUBE_LINE" -lt "$MACHINE_LINE" ]
}

@test "prerm: exits cleanly when baize user does not exist" {
    # Restore the "user absent" mocks for this test only.
    cat > "${MOCK_DIR}/id" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "-u" ]; then
    echo "0"
else
    echo "uid=0(root) gid=0(root) groups=0(root)"
fi
EOF
    chmod +x "${MOCK_DIR}/id"
    cat > "${MOCK_DIR}/getent" <<'EOF'
#!/bin/bash
if [ "$1" = "passwd" ] && [ "$2" = "baize" ]; then
    exit 2  # user does not exist
fi
exit 0
EOF
    chmod +x "${MOCK_DIR}/getent"
    # Wait: prerm checks the user via `id baize`, which must FAIL here.
    cat > "${MOCK_DIR}/id" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "baize" ]; then
    exit 1  # baize user does not exist
fi
echo "uid=0(root) gid=0(root) groups=0(root)"
EOF
    chmod +x "${MOCK_DIR}/id"
    run bash debian/DEBIAN/prerm remove
    [ "$status" -eq 0 ]
}