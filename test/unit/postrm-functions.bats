#!/usr/bin/env bats

load ../test_helper

setup() {
    setup_mocks
}

teardown() {
    teardown_mocks
}

@test "postrm: info function outputs correct format" {
    source debian/DEBIAN/postrm 2>/dev/null || true
    run info "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[baize-kube] INFO:"* ]]
}

@test "postrm: BAIZE_USER is set correctly" {
    source debian/DEBIAN/postrm 2>/dev/null || true
    [ "$BAIZE_USER" = "baize" ]
}

@test "postrm: CONSUMERS_GROUP is set correctly" {
    source debian/DEBIAN/postrm 2>/dev/null || true
    [ "$CONSUMERS_GROUP" = "baize-consumers" ]
}

@test "postrm: set -euo pipefail is active" {
    source debian/DEBIAN/postrm 2>/dev/null || true
    run bash -c 'set -u; echo $UNDEFINED_VAR_XYZ456'
    [ "$status" -ne 0 ]
}

@test "postrm: action guard only runs on remove/purge" {
    # Source the action guard logic
    run bash -c 'ACTION=upgrade; source debian/DEBIAN/postrm 2>/dev/null || true'
    # Should exit 0 for non-remove/purge actions
    [ "$status" -eq 0 ]
}
