# AGENTS.md — baize-kube

## Tech Stack
- Debian packaging (dpkg-deb, shell scripts)
- Rootless minikube on arm64 (Raspberry Pi 5)
- GitHub Actions for CI/CD

## Design Principles

### External Dependency Version Verification

Before using any external dependency (GitHub Action, apt package, container image,
npm package, etc.), verify the latest stable version against its authoritative
source. Never assume a version number from memory or training data.

**For GitHub Actions specifically:**

1. Check the action's releases page for the latest stable major version.
2. Prefer `@v` major version tags (e.g., `@v7`, `@v3`) — these float to the
   latest minor/patch within the major version, providing automatic security
   and bug fixes without breaking changes.
3. Do NOT use `@main`, `@master`, or branch references — these are mutable and
   can introduce breaking changes without warning.
4. Commit SHAs provide maximum supply-chain security but require manual updates
   for every patch. Use only when the project's security posture demands it.

**For all external dependencies:**

- Verify the version against the official source (releases page, package
  registry, official documentation) — not against blog posts, Stack Overflow,
  or training data.
- This extends the `authoritative-reference` skill's "verify before acting"
  mandate to dependency versioning.

## Key Rules
- No assumption: every claim must be verified against authoritative sources
- Pipeline: all changes go through Phase A → B → C → CR
- Conventional commits: `type(scope): description` with mandatory body
- Shell scripts: `set -euo pipefail` required in all scripts
