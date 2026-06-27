.PHONY: all build clean lint test install

PACKAGE := baize-kube
VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")
ARCH := arm64
DEB := $(PACKAGE)_$(VERSION)_$(ARCH).deb

all: lint build

build:
	@mkdir -p debian/usr/share/doc/baize-kube
	@cp doc/*.md debian/usr/share/doc/baize-kube/
	@sed -i.bak "s/^Version:.*/Version: $(VERSION)/" debian/DEBIAN/control
	dpkg-deb --build debian $(DEB)
	@echo "Built: $(DEB)"

lint:
	@echo "Running shellcheck..."
	shellcheck debian/DEBIAN/postinst
	shellcheck debian/DEBIAN/postrm
	shellcheck debian/DEBIAN/prerm 2>/dev/null || true
	shellcheck debian/DEBIAN/config 2>/dev/null || true
	shellcheck debian/usr/local/bin/baize-kube-add-consumer
	shellcheck debian/usr/local/bin/baize-kube-remove-consumer
	shellcheck debian/usr/local/bin/baize-kube-list-consumers
	shellcheck debian/usr/local/bin/baize-kube-update-kubeconfig
	@echo "Running lintian..."
	lintian $(DEB) 2>/dev/null || echo "lintian not installed (install: sudo apt install lintian)"

test:
	bats test/

clean:
	rm -f $(DEB)
	rm -rf debian/usr/share/doc/baize-kube/
	@if [ -f debian/DEBIAN/control.bak ]; then mv debian/DEBIAN/control.bak debian/DEBIAN/control; fi

install:
	sudo dpkg -i $(DEB)
