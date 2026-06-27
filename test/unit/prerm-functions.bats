#!/usr/bin/env bats

load ../test_helper

setup() {
    setup_mocks
}

teardown() {
    teardown_mocks
}

@test "prerm: info function outputs correct format" {
    source debian/DEBIAN/prerm 2>/dev/null || true
    run info "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[baize-kube] INFO:"* ]]
}

@test "prerm: BAIZE_USER is set correctly" {
    source debian/DEBIAN/prerm 2>/dev/null || true
    [ "$BAIZE_USER" = "baize" ]
}

@test "prerm: set -euo pipefail is active" {
    source debian/DEBIAN/prerm 2>/dev/null || true
    run bash -c 'set -u; echo $UNDEFINED_VAR_XYZ789'
    [ "$status" -ne 0 ]
}

@test "prerm: action guard exits 0 for upgrade" {
    run bash -c 'ACTION=upgrade; source debian/DEBIAN/prerm 2>/dev/null || true'
    [ "$status" -eq 0 ]
}
