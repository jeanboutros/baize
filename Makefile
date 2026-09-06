.PHONY: all build clean lint test install uninstall

PACKAGE := baize-kube
VERSION ?= $(shell TAG=$$(git describe --tags --abbrev=0 2>/dev/null); if [ -n "$$TAG" ]; then echo "$$TAG" | sed 's/^v//'; else echo "1.0.0"; fi)
ARCH := arm64
DEB := $(PACKAGE)_$(VERSION)_$(ARCH).deb

all: build lint

build:
	@# Copy documentation into the package tree (Policy 12: every package
	@# ships its license text as /usr/share/doc/<pkg>/copyright).
	@mkdir -p debian/usr/share/doc/baize-kube
	@cp doc/*.md debian/usr/share/doc/baize-kube/
	@cp LICENSE debian/usr/share/doc/baize-kube/copyright
	@# Regenerate the changelog every build (rm first: gzip refuses to
	@# overwrite an existing .gz, which broke rebuilds).
	@rm -f debian/usr/share/doc/baize-kube/changelog debian/usr/share/doc/baize-kube/changelog.gz
	@# Changelog version is INJECTED from $(VERSION) — a hardcoded version
	@# here would disagree with the control file (caught by loop-2 review).
	@# Trailer date generated with `date -R` (RFC 2822, +0000 form) per
	@# Policy 12.7 — a hardcoded date or "+00:00" fails dpkg-parsechangelog.
	@printf 'baize-kube ($(VERSION)) unstable; urgency=medium\n\n  * See doc/ for this release.\n\n -- Jean Boutros <jean.boutros@example.com>  ' > debian/usr/share/doc/baize-kube/changelog
	@date -R >> debian/usr/share/doc/baize-kube/changelog
	@gzip -9n debian/usr/share/doc/baize-kube/changelog
	@# Validate VERSION format (Debian Policy: must start with digit, only [A-Za-z0-9.+~:-])
	@if ! echo "$(VERSION)" | grep -qE '^[0-9][A-Za-z0-9.+~:-]*$$'; then \
		echo "ERROR: VERSION '$(VERSION)' is not a valid Debian version string"; \
		exit 1; \
	fi
	@# Normalize file modes BEFORE building: dpkg-deb --root-owner-group fixes
	@# OWNERSHIP but preserves MODES — a group-writable root-run script in the
	@# .deb is both a lintian error and a privilege-escalation smell.
	@# Directories too: the build host's 002 umask leaks 0775 dirs into the deb.
	@find debian -type d -exec chmod 755 {} +
	@find debian -type f -exec chmod a-x,go-w {} +
	@chmod 755 debian/DEBIAN/postinst debian/DEBIAN/prerm debian/DEBIAN/postrm debian/DEBIAN/config
	@chmod 755 debian/usr/bin/baize-kube-*
	@chmod 755 debian/usr/lib/baize-kube/complete-install
	@# Inject version into control file, with a correct backup dance:
	@#   ORIG = pristine copy of control (BEFORE any sed; trap armed only
	@#         AFTER this cp succeeds, or a failed cp would let the trap
	@#         move an EMPTY mktemp over the real control)
	@#   NEW  = sed'd + Installed-Size-augmented content
	@#   restore uses cp (not mv): mv would carry mktemp's 0600 mode onto
	@#   the tree's control; cp into the existing file preserves its mode
	@#   NOTE: no # comments inside the && chain below — a comment line
	@#   between backslash-continued recipe lines splits the chain into a
	@#   new shell where the variables are unset.
	@ORIG=$$(mktemp) && NEW=$$(mktemp) && \
	cp debian/DEBIAN/control "$$ORIG" && \
	trap 'rm -f "$$NEW"; cp "$$ORIG" debian/DEBIAN/control; rm -f "$$ORIG"' EXIT && \
	sed -e "s/^Version:.*/Version: $(VERSION)/" -e "/^Installed-Size:/d" "$$ORIG" > "$$NEW" && \
	printf 'Installed-Size: %s\n' "$$(du -sk debian/usr 2>/dev/null | cut -f1)" >> "$$NEW" && \
	cp "$$NEW" debian/DEBIAN/control && \
	rm -f $(DEB) && \
	dpkg-deb --build --root-owner-group debian $(DEB) ; \
	build_rc=$$? ; \
	trap - EXIT ; \
	rm -f "$$NEW" ; \
	cp "$$ORIG" debian/DEBIAN/control && rm -f "$$ORIG" ; \
	[ $$build_rc -eq 0 ] && echo "Built: $(DEB)" || exit $$build_rc

lint: build
	@echo "Running shellcheck..."
	@# Fail the target on ANY failing script. NOTE: the loop MUST run in
	@# this shell — a `grep | while read` pipeline puts the while-loop in a
	@# SUBSHELL, whose rc=1 can never reach this shell's exit (a previous
	@# version of this recipe did exactly that and always exited 0).
	@# for-in-$$(...) is POSIX/dash-safe (recipe lines run /bin/sh) and
	@# works because .check-scripts paths contain no whitespace.
	@rc=0; for f in $$(grep -v '^#' .check-scripts | grep -v '^$$'); do \
		shellcheck "$$f" || rc=1; \
	done; exit $$rc
	@echo "Running lintian..."
	@# --fail-on error: lintian ERRORS must gate the build (they were
	@# previously swallowed by '|| true', so FHS/policy violations shipped).
	@if command -v lintian > /dev/null 2>&1; then \
		lintian --fail-on error $(DEB) || exit 1; \
	else \
		echo "lintian not installed (install: sudo apt install lintian) — skipping"; \
	fi

test:
	@if ! command -v bats > /dev/null 2>&1; then \
		echo "bats not installed (install: sudo apt install bats)"; \
		exit 1; \
	fi
	bats test/unit/*.bats test/integration/*.bats

clean:
	rm -f baize-kube_*_arm64.deb
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
