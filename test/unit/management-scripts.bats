#!/usr/bin/env bats

load ../test_helper

setup() {
    setup_mocks
}

teardown() {
    teardown_mocks
}

@test "add-consumer: script exists and is executable" {
    [ -x "debian/usr/local/bin/baize-kube-add-consumer" ]
}

@test "add-consumer: has set -euo pipefail" {
    head -5 debian/usr/local/bin/baize-kube-add-consumer | grep -q "set -euo pipefail"
}

@test "add-consumer: no eval echo in script" {
    run grep "eval echo" debian/usr/local/bin/baize-kube-add-consumer
    [ "$status" -ne 0 ]
}

@test "remove-consumer: script exists and is executable" {
    [ -x "debian/usr/local/bin/baize-kube-remove-consumer" ]
}

@test "remove-consumer: has set -euo pipefail" {
    head -5 debian/usr/local/bin/baize-kube-remove-consumer | grep -q "set -euo pipefail"
}

@test "remove-consumer: no eval echo in script" {
    run grep "eval echo" debian/usr/local/bin/baize-kube-remove-consumer
    [ "$status" -ne 0 ]
}

@test "list-consumers: script exists and is executable" {
    [ -x "debian/usr/local/bin/baize-kube-list-consumers" ]
}

@test "list-consumers: has set -euo pipefail" {
    head -5 debian/usr/local/bin/baize-kube-list-consumers | grep -q "set -euo pipefail"
}

@test "update-kubeconfig: script exists and is executable" {
    [ -x "debian/usr/local/bin/baize-kube-update-kubeconfig" ]
}

@test "update-kubeconfig: has set -euo pipefail" {
    head -5 debian/usr/local/bin/baize-kube-update-kubeconfig | grep -q "set -euo pipefail"
}

@test "update-kubeconfig: no eval echo in script" {
    run grep "eval echo" debian/usr/local/bin/baize-kube-update-kubeconfig
    [ "$status" -ne 0 ]
}
