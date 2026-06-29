.PHONY: all build clean lint test install uninstall

PACKAGE := baize-kube
VERSION ?= $(shell TAG=$$(git describe --tags --abbrev=0 2>/dev/null); if [ -n "$$TAG" ]; then echo "$$TAG" | sed 's/^v//'; else echo "1.0.0"; fi)
ARCH := arm64
DEB := $(PACKAGE)_$(VERSION)_$(ARCH).deb

all: lint build

build:
	@mkdir -p debian/usr/share/doc/baize-kube
	@cp doc/*.md debian/usr/share/doc/baize-kube/
	@# Validate VERSION format (Debian Policy: must start with digit, only [A-Za-z0-9.+~:-])
	@if ! echo "$(VERSION)" | grep -qE '^[0-9][A-Za-z0-9.+~:-]*$$'; then \
		echo "ERROR: VERSION '$(VERSION)' is not a valid Debian version string"; \
		exit 1; \
	fi
	@# Inject version into control file (preserve original)
	@cp debian/DEBIAN/control debian/DEBIAN/control.orig
	@sed "s/^Version:.*/Version: $(VERSION)/" debian/DEBIAN/control.orig > debian/DEBIAN/control
	dpkg-deb --build --root-owner-group debian $(DEB)
	@# Restore original control file
	@mv debian/DEBIAN/control.orig debian/DEBIAN/control
	@echo "Built: $(DEB)"

lint:
	@echo "Running shellcheck..."
	@grep -v '^#' .check-scripts | grep -v '^$$' | while read -r f; do \
		shellcheck "$$f"; \
	done
	@echo "Running lintian..."
	lintian $(DEB) 2>/dev/null || echo "lintian not installed (install: sudo apt install lintian)"

test:
	@if ! command -v bats > /dev/null 2>&1; then \
		echo "bats not installed (install: sudo apt install bats)"; \
		exit 1; \
	fi
	bats test/

clean:
	rm -f $(DEB)
	rm -rf debian/usr/share/doc/baize-kube/

install:
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "This target requires root privileges."; \
		echo "Re-running with sudo..."; \
		sudo make install; \
	else \
		dpkg -i $(DEB); \
	fi

uninstall:
	@echo "Removing baize-kube..."
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "This target requires root privileges."; \
		echo "Re-running with sudo..."; \
		sudo make uninstall; \
	else \
		dpkg --purge baize-kube 2>/dev/null || echo "Package not installed."; \
		echo "Uninstall complete."; \
	fi
