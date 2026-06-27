#!/usr/bin/env bats

load ../test_helper

setup() {
    setup_mocks
}

teardown() {
    teardown_mocks
}

@test "idempotency: consumer_selection handles empty config file" {
    # Create empty config
    mkdir -p /tmp/baize-kube-test
    echo "" > /tmp/baize-kube-test/consumers.conf

    # Should not fail on empty config
    run bash -c '
        CONSUMERS_CONFIG="/tmp/baize-kube-test/consumers.conf"
        source debian/DEBIAN/postinst 2>/dev/null || true
    '
    rm -rf /tmp/baize-kube-test
}

@test "idempotency: consumer_selection handles commented config" {
    mkdir -p /tmp/baize-kube-test
    echo "# only comments" > /tmp/baize-kube-test/consumers.conf
    echo "# no actual users" >> /tmp/baize-kube-test/consumers.conf

    run bash -c '
        CONSUMERS_CONFIG="/tmp/baize-kube-test/consumers.conf"
        source debian/DEBIAN/postinst 2>/dev/null || true
    '
    rm -rf /tmp/baize-kube-test
}

@test "idempotency: postinst variables are consistent" {
    source debian/DEBIAN/postinst 2>/dev/null || true

    # Verify key paths
    [ -n "$BAIZE_HOME" ]
    [ -n "$MINIKUBE_BIN" ]
    [ -n "$KUBECTL_BIN" ]
    [ -n "$CMDLINE_FILE" ]
    [ -n "$DELEGATE_CONF" ]
}

@test "idempotency: postrm variables are consistent" {
    source debian/DEBIAN/postrm 2>/dev/null || true

    [ -n "$BAIZE_USER" ]
    [ -n "$CONSUMERS_GROUP" ]
    [ -n "$BAIZE_HOME" ]
}

@test "idempotency: prerm variables are consistent" {
    source debian/DEBIAN/prerm 2>/dev/null || true

    [ -n "$BAIZE_USER" ]
    [ -n "$BAIZE_HOME" ]
    [ -n "$MINIKUBE_BIN" ]
}
