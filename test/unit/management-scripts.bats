#!/usr/bin/env bats

load ../test_helper

setup() {
    setup_mocks
}

teardown() {
    teardown_mocks
}

@test "add-consumer: script exists and is executable" {
    [ -x "debian/usr/bin/baize-kube-add-consumer" ]
}

@test "add-consumer: has set -euo pipefail" {
    head -5 debian/usr/bin/baize-kube-add-consumer | grep -q "set -euo pipefail"
}

@test "add-consumer: no eval echo in script" {
    run grep "eval echo" debian/usr/bin/baize-kube-add-consumer
    [ "$status" -ne 0 ]
}

@test "remove-consumer: script exists and is executable" {
    [ -x "debian/usr/bin/baize-kube-remove-consumer" ]
}

@test "remove-consumer: has set -euo pipefail" {
    head -5 debian/usr/bin/baize-kube-remove-consumer | grep -q "set -euo pipefail"
}

@test "remove-consumer: no eval echo in script" {
    run grep "eval echo" debian/usr/bin/baize-kube-remove-consumer
    [ "$status" -ne 0 ]
}

@test "list-consumers: script exists and is executable" {
    [ -x "debian/usr/bin/baize-kube-list-consumers" ]
}

@test "list-consumers: has set -euo pipefail" {
    head -5 debian/usr/bin/baize-kube-list-consumers | grep -q "set -euo pipefail"
}

@test "update-kubeconfig: script exists and is executable" {
    [ -x "debian/usr/bin/baize-kube-update-kubeconfig" ]
}

@test "update-kubeconfig: has set -euo pipefail" {
    head -5 debian/usr/bin/baize-kube-update-kubeconfig | grep -q "set -euo pipefail"
}

@test "update-kubeconfig: no eval echo in script" {
    run grep "eval echo" debian/usr/bin/baize-kube-update-kubeconfig
    [ "$status" -ne 0 ]
}

@test "update-admin-kubeconfig: script exists and is executable" {
    [ -x "debian/usr/bin/baize-kube-update-admin-kubeconfig" ]
}

@test "update-admin-kubeconfig: has set -euo pipefail" {
    head -5 debian/usr/bin/baize-kube-update-admin-kubeconfig | grep -q "set -euo pipefail"
}

@test "update-admin-kubeconfig: no eval echo in script" {
    run grep "eval echo" debian/usr/bin/baize-kube-update-admin-kubeconfig
    [ "$status" -ne 0 ]
}

@test "update-admin-kubeconfig: writes with umask 077, never /tmp staging" {
    grep -q "umask 077" debian/usr/bin/baize-kube-update-admin-kubeconfig
    ! grep -q "/tmp/" debian/usr/bin/baize-kube-update-admin-kubeconfig
}

@test "update-kubeconfig: decodes base64 token (regression: BLOCKER fix)" {
    grep -q "jsonpath='{.data.token}' | base64 -d" debian/usr/bin/baize-kube-update-kubeconfig
}

@test "update-kubeconfig: refuses symlinked kubeconfig destinations" {
    grep -q 'is a symlink' debian/usr/bin/baize-kube-update-kubeconfig
    grep -q 'mv -T' debian/usr/bin/baize-kube-update-kubeconfig
}

@test "add-consumer: refuses symlinked kubeconfig destinations" {
    grep -q 'is a symlink' debian/usr/bin/baize-kube-add-consumer
    grep -q 'mv -T' debian/usr/bin/baize-kube-add-consumer
}

@test "postinst: admin kubeconfig export uses no /tmp staging" {
    ! grep -q "tmp_kubeconfig\|/tmp/baize-kube" debian/DEBIAN/postinst
}

@test "postinst: pinned minikube hash mismatch is FATAL" {
    grep -q "refusing to install" debian/DEBIAN/postinst
}

@test "postinst: existing minikube binary is re-verified against pinned hash" {
    grep -q "INSTALLED_SHA" debian/DEBIAN/postinst
}

@test "config: db_input/db_go take NO forwarded arguments (debconf protocol)" {
    # Regression: forwarding dpkg's "$@" into db_input/db_go corrupted the
    # debconf protocol (INPUT rejects >2 args with code 20) and the
    # question was never asked. The calls must be argument-free.
    ! grep -q 'db_input.*"\$@"' debian/DEBIAN/config
    ! grep -q 'db_go.*"\$@"' debian/DEBIAN/config
}

@test "add-consumer: chown/chmod happen on the TEMP file, before the rename" {
    # Regression (security): chown-after-rename allowed a racing consumer
    # to symlink-swap the destination and get an arbitrary file chowned.
    # The order must be: chown tmp; chmod tmp; mv -T tmp dest.
    local f=debian/usr/bin/baize-kube-add-consumer
    local chown_line mv_line
    chown_line=$(grep -n 'chown "${USERNAME}:" "$tmp_config"' "$f" | head -1 | cut -d: -f1)
    mv_line=$(grep -n 'mv -T "$tmp_config" "$kubeconfig_path"' "$f" | head -1 | cut -d: -f1)
    [ -n "$chown_line" ]
    [ -n "$mv_line" ]
    [ "$chown_line" -lt "$mv_line" ]
    # and no chown/chmod on the destination AFTER the rename
    ! sed -n "$((mv_line + 1)),\$p" "$f" | grep -q 'chown.*"\$kubeconfig_path"'
}

@test "update-kubeconfig: chown/chmod happen on the TEMP file, before the rename" {
    local f=debian/usr/bin/baize-kube-update-kubeconfig
    local chown_line mv_line
    chown_line=$(grep -n 'chown "${username}:" "$tmp_config"' "$f" | head -1 | cut -d: -f1)
    mv_line=$(grep -n 'mv -T "$tmp_config" "$kubeconfig_path"' "$f" | head -1 | cut -d: -f1)
    [ -n "$chown_line" ]
    [ -n "$mv_line" ]
    [ "$chown_line" -lt "$mv_line" ]
    ! sed -n "$((mv_line + 1)),\$p" "$f" | grep -q 'chown.*"\$kubeconfig_path"'
}

@test "add-consumer: no dangling references to removed BAIZE_* variables" {
    # Regression: loop-2 removed the variable definitions but left one
    # reference in an error message, breaking it under set -u.
    ! grep -q 'BAIZE_RUNTIME_DIR\|BAIZE_CONTAINER_HOST\|BAIZE_UID' debian/usr/bin/baize-kube-add-consumer
    ! grep -q 'BAIZE_RUNTIME_DIR\|BAIZE_CONTAINER_HOST\|BAIZE_UID' debian/usr/bin/baize-kube-remove-consumer
    ! grep -q 'BAIZE_RUNTIME_DIR\|BAIZE_CONTAINER_HOST\|BAIZE_UID' debian/usr/bin/baize-kube-list-consumers
    ! grep -q 'BAIZE_RUNTIME_DIR\|BAIZE_CONTAINER_HOST\|BAIZE_UID' debian/usr/bin/baize-kube-update-kubeconfig
}

@test "update-admin-kubeconfig: uses runuser, not sudo (undeclared dependency)" {
    ! grep -q 'sudo -u' debian/usr/bin/baize-kube-update-admin-kubeconfig
    grep -q 'runuser -u' debian/usr/bin/baize-kube-update-admin-kubeconfig
}

@test "update-admin-kubeconfig: pins KUBECONFIG to baize's live kubeconfig" {
    grep -q 'KUBECONFIG="${BAIZE_HOME}/.kube/config"' debian/usr/bin/baize-kube-update-admin-kubeconfig
}

@test "recovery paths call the helper by absolute path" {
    for f in add-consumer remove-consumer list-consumers update-kubeconfig; do
        grep -q '/usr/bin/baize-kube-update-admin-kubeconfig' "debian/usr/bin/baize-kube-$f"
        ! grep -q 'command -v baize-kube-update-admin' "debian/usr/bin/baize-kube-$f"
    done
}
