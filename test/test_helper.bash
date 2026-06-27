#!/bin/bash
# Test helpers for baize-kube bats tests

# Mock commands that require root or system access
setup_mocks() {
    # Create a temporary directory for mock binaries
    MOCK_DIR="$(mktemp -d)"
    export PATH="${MOCK_DIR}:${PATH}"

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

    # Mock minikube
    cat > "${MOCK_DIR}/minikube" <<'EOF'
#!/bin/bash
echo "minikube $*" >> /tmp/baize-kube-test.log
EOF
    chmod +x "${MOCK_DIR}/minikube"

    # Mock kubectl
    cat > "${MOCK_DIR}/kubectl" <<'EOF'
#!/bin/bash
echo "kubectl $*" >> /tmp/baize-kube-test.log
EOF
    chmod +x "${MOCK_DIR}/kubectl"

    # Clean log
    rm -f /tmp/baize-kube-test.log
}

teardown_mocks() {
    rm -rf "${MOCK_DIR}"
    rm -f /tmp/baize-kube-test.log
}
