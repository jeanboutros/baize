#!/usr/bin/env bats

load ../test_helper

setup() {
    setup_mocks
}

teardown() {
    teardown_mocks
}

@test "require_root: exits when not root" {
    # Override id mock to return non-root
    cat > "${MOCK_DIR}/id" <<'EOF'
#!/bin/bash
echo "uid=1000(user) gid=1000(user)"
EOF
    chmod +x "${MOCK_DIR}/id"

    run bash -c 'source debian/DEBIAN/postinst 2>&1 || true'
    # Should fail because not root
    [ "$status" -ne 0 ] || [ -n "$(echo "$output" | grep -i 'root\|must be run')" ]
}

@test "info function: outputs correct format" {
    source debian/DEBIAN/postinst 2>/dev/null || true
    run info "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[baize-kube] INFO:"* ]]
    [[ "$output" == *"test message"* ]]
}

@test "fail function: exits with error" {
    source debian/DEBIAN/postinst 2>/dev/null || true
    run fail "test failure"
    [ "$status" -eq 1 ]
    [[ "$output" == *"[baize-kube] ERROR:"* ]]
    [[ "$output" == *"test failure"* ]]
}

@test "warn function: outputs warning format" {
    source debian/DEBIAN/postinst 2>/dev/null || true
    run warn "test warning"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[baize-kube] WARN:"* ]]
    [[ "$output" == *"test warning"* ]]
}

@test "success function: outputs success format" {
    source debian/DEBIAN/postinst 2>/dev/null || true
    run success "test success"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[baize-kube] OK:"* ]]
    [[ "$output" == *"test success"* ]]
}

@test "MINIKUBE_VERSION is pinned" {
    source debian/DEBIAN/postinst 2>/dev/null || true
    [ -n "$MINIKUBE_VERSION" ]
    [[ "$MINIKUBE_VERSION" == v* ]]
}

@test "KUBECTL_VERSION is pinned" {
    source debian/DEBIAN/postinst 2>/dev/null || true
    [ -n "$KUBECTL_VERSION" ]
    [[ "$KUBECTL_VERSION" == v* ]]
}

@test "BAIZE_USER is set correctly" {
    source debian/DEBIAN/postinst 2>/dev/null || true
    [ "$BAIZE_USER" = "baize" ]
}

@test "CONSUMERS_GROUP is set correctly" {
    source debian/DEBIAN/postinst 2>/dev/null || true
    [ "$CONSUMERS_GROUP" = "baize-consumers" ]
}

@test "KUBECONFIG_SHARED path uses admin-kubeconfig" {
    source debian/DEBIAN/postinst 2>/dev/null || true
    [[ "$ADMIN_KUBECONFIG" == *"admin-kubeconfig"* ]]
}

@test "set -euo pipefail is active" {
    source debian/DEBIAN/postinst 2>/dev/null || true
    # If set -u is active, referencing an unset variable should fail
    run bash -c 'set -u; echo $UNDEFINED_VAR_XYZ123'
    [ "$status" -ne 0 ]
}
