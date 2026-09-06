#!/bin/bash
# Test helpers for baize-kube bats tests

# Mock commands that require root or system access
setup_mocks() {
    # Create a temporary directory for mock binaries
    MOCK_DIR="$(mktemp -d)"
    export PATH="${MOCK_DIR}:${PATH}"

    # Predefine debconf helper functions. postinst sources debconf's
    # confmodule, which (a) execs an interactive frontend that needs a tty
    # and (b) redirects the shell's stdout for its protocol — both fatal
    # for a test harness. postinst skips sourcing confmodule when db_get
    # is already defined, so defining stubs here neutralizes it.
    db_get()     { RET=""; return 0; }
    db_set()     { return 0; }
    db_input()   { return 0; }
    db_go()      { return 0; }
    db_purge()   { return 0; }
    db_stop()    { return 0; }
    export -f db_get db_set db_input db_go db_purge db_stop

    # Mock systemctl
    cat > "${MOCK_DIR}/systemctl" <<'EOF'
#!/bin/bash
echo "systemctl $*" >> /tmp/baize-kube-test.log
EOF
    chmod +x "${MOCK_DIR}/systemctl"

    # Mock loginctl
    cat > "${MOCK_DIR}/loginctl" <<'EOF'
#!/bin/bash
echo "loginctl $*" >> /tmp/baize-kube-test.log
EOF
    chmod +x "${MOCK_DIR}/loginctl"

    # Mock useradd
    cat > "${MOCK_DIR}/useradd" <<'EOF'
#!/bin/bash
echo "useradd $*" >> /tmp/baize-kube-test.log
EOF
    chmod +x "${MOCK_DIR}/useradd"

    # Mock usermod
    cat > "${MOCK_DIR}/usermod" <<'EOF'
#!/bin/bash
echo "usermod $*" >> /tmp/baize-kube-test.log
EOF
    chmod +x "${MOCK_DIR}/usermod"

    # Guard rails for DESTRUCTIVE IDENTITY commands. The maintainer
    # scripts under test call userdel/groupadd/groupdel/loginctl against
    # the LIVE system; when the suite runs as root those must never run
    # for real (a loop-4 review found exactly that hazard).
    cat > "${MOCK_DIR}/userdel" <<'EOF'
#!/bin/bash
echo "userdel $*" >> /tmp/baize-kube-test.log
# NEVER perform a real userdel from the test suite.
exit 0
EOF
    chmod +x "${MOCK_DIR}/userdel"

    for cmd in groupadd groupdel loginctl; do
        cat > "${MOCK_DIR}/${cmd}" <<EOF
#!/bin/bash
echo "${cmd} \$*" >> /tmp/baize-kube-test.log
exit 0
EOF
        chmod +x "${MOCK_DIR}/${cmd}"
    done

    # NOTE: rm and sed are NOT mocked — the tests use them for their own
    # infrastructure (building patched copies, cleaning sandboxes), and a
    # global mock broke that (loop-4). Instead, every test that EXECUTES
    # a maintainer script must patch the script's system paths (BAIZE_HOME,
    # KUBECONFIG_DIR, ...) into a sandbox under ${MOCK_DIR}, so the real
    # rm/sed only ever see sandbox paths. userdel and friends stay mocked
    # above because they take usernames, not paths, and cannot be
    # redirected by patching a variable.

    # Mock podman — stateful machine registry via /tmp/baize-kube-test-machines
    cat > "${MOCK_DIR}/podman" <<'EOF'
#!/bin/bash
LOG=/tmp/baize-kube-test.log
MACHINES=/tmp/baize-kube-test-machines
cmd="${1:-}"
case "$cmd" in
    machine)
        sub="${2:-}"
        name="${!#}"  # last arg is the machine name (or flag value)
        case "$sub" in
            ls|list)
                echo "podman machine $*" >> "$LOG"
                if [ -f "$MACHINES" ] && grep -qx "minikube" "$MACHINES"; then
                    echo "minikube"
                fi
                exit 0
                ;;
            init)
                echo "podman machine $*" >> "$LOG"
                mkdir -p "$(dirname "$MACHINES")"
                echo "minikube" >> "$MACHINES"
                exit 0
                ;;
            start|stop|rm)
                echo "podman machine $*" >> "$LOG"
                exit 0
                ;;
            *)
                echo "podman $*" >> "$LOG"
                exit 0
                ;;
        esac
        ;;
    info)
        echo "podman $*" >> "$LOG"
        exit 0
        ;;
    *)
        echo "podman $*" >> "$LOG"
        exit 0
        ;;
esac
EOF
    chmod +x "${MOCK_DIR}/podman"
    rm -f /tmp/baize-kube-test-machines

    # Mock groupadd
    cat > "${MOCK_DIR}/groupadd" <<'EOF'
#!/bin/bash
echo "groupadd $*" >> /tmp/baize-kube-test.log
EOF
    chmod +x "${MOCK_DIR}/groupadd"

    # Mock passwd
    cat > "${MOCK_DIR}/passwd" <<'EOF'
#!/bin/bash
echo "passwd $*" >> /tmp/baize-kube-test.log
EOF
    chmod +x "${MOCK_DIR}/passwd"

    # Mock curl
    cat > "${MOCK_DIR}/curl" <<'EOF'
#!/bin/bash
echo "curl $*" >> /tmp/baize-kube-test.log
EOF
    chmod +x "${MOCK_DIR}/curl"

    # Mock id
    cat > "${MOCK_DIR}/id" <<'EOF'
#!/bin/bash
if [ "$1" = "-u" ]; then
    echo "0"  # pretend to be root
else
    echo "uid=0(root) gid=0(root) groups=0(root)"
fi
EOF
    chmod +x "${MOCK_DIR}/id"

    # Mock getent
    cat > "${MOCK_DIR}/getent" <<'EOF'
#!/bin/bash
if [ "$1" = "group" ] && [ "$2" = "baize-consumers" ]; then
    exit 2  # group does not exist
elif [ "$1" = "group" ] && [ "$2" = "baize-admins" ]; then
    exit 2  # group does not exist
elif [ "$1" = "group" ] && [ "$2" = "kvm" ]; then
    echo "kvm:x:993:"
    exit 0  # kvm group exists (Pi 5)
elif [ "$1" = "passwd" ] && [ "$2" = "baize" ]; then
    exit 2  # user does not exist
fi
exit 0
EOF
    chmod +x "${MOCK_DIR}/getent"

    # Mock runuser
    cat > "${MOCK_DIR}/runuser" <<'EOF'
#!/bin/bash
echo "runuser $*" >> /tmp/baize-kube-test.log
EOF
    chmod +x "${MOCK_DIR}/runuser"

    # Mock dpkg
    cat > "${MOCK_DIR}/dpkg" <<'EOF'
#!/bin/bash
echo "dpkg $*" >> /tmp/baize-kube-test.log
EOF
    chmod +x "${MOCK_DIR}/dpkg"

    # Mock sha256sum
    cat > "${MOCK_DIR}/sha256sum" <<'EOF'
#!/bin/bash
# Return a matching hash for testing
echo "abc123  /tmp/test"
EOF
    chmod +x "${MOCK_DIR}/sha256sum"

    # Mock minikube — version reporting + completion support
    cat > "${MOCK_DIR}/minikube" <<'EOF'
#!/bin/bash
echo "minikube $*" >> /tmp/baize-kube-test.log
if [ "$1" = "version" ]; then
    echo "minikube version: v1.39.0"
    exit 0
fi
if [ "$1" = "completion" ] && [ "$2" = "bash" ]; then
    echo "# bash completion for minikube"
    exit 0
fi
EOF
    chmod +x "${MOCK_DIR}/minikube"

    # Mock kubectl — supports version --client (new format) and completion
    cat > "${MOCK_DIR}/kubectl" <<'EOF'
#!/bin/bash
echo "kubectl $*" >> /tmp/baize-kube-test.log
if [ "$1" = "version" ] && [ "$2" = "--client" ]; then
    echo "Client Version: v1.37.0"
    echo "Kustomize Version: v5.5.4"
    exit 0
fi
if [ "$1" = "completion" ]; then
    echo "# bash completion for kubectl"
    exit 0
fi
EOF
    chmod +x "${MOCK_DIR}/kubectl"

    # Clean log
    rm -f /tmp/baize-kube-test.log
    rm -f /tmp/baize-kube-test-machines
}

teardown_mocks() {
    # /bin/rm (NOT the PATH rm): MOCK_DIR contains the rm mock itself, so
    # once the first line really deletes it, any later PATH-rm call would
    # 127. Absolute path sidesteps the mock entirely.
    /bin/rm -rf "${MOCK_DIR}"
    /bin/rm -f /tmp/baize-kube-test.log /tmp/baize-kube-test-machines
    /bin/rm -rf /tmp/baize-kube-test
}

# Source a maintainer script (postinst/prerm/postrm) for unit testing.
# The scripts start with `set -euo pipefail`, which would otherwise leak into
# the bats test shell and abort the whole test file on the first failing
# command. We source the script, then explicitly reset the strict-mode
# options so bats' own machinery keeps working. (Individual tests that
# care about strict mode opt back in.)
source_postinst_lib() {
    local script="$1"
    # shellcheck source=/dev/null
    source "$script" > /dev/null 2>&1 || true
    set +e
    set +u
    set +o pipefail
}
