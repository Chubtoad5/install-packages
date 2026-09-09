# Changelog — install-packages

## 2026-09-09 — Idempotence release (feature/idempotence-phase2)

Suite-wide idempotence and correctness pass. `install_packages.sh` is now safe to call
repeatedly and safe to call from automation under `set -e`: every failure path restores the
host's package-manager configuration, and every archive it produces is either complete or
absent — never truncated.

### Fixed
- **`save online` saves before installing.** The tarball is built first, so the archive
  captures the requested packages and their dependencies even when some are already present
  on the build host.
- **RHEL-family `save` bundles the full dependency closure** (`dnf download --resolve
  --alldeps`), including packages already installed on the build host. Archives are larger,
  but offline installs onto minimal images no longer fail on missing dependencies.
- **`offline` mode always restores the original package-manager configuration** — apt
  sources, the dnf repo file, the zypper repo list — even when the install fails or is
  interrupted. This is enforced by an `EXIT` trap around a scoped temporary local repository;
  the script never removes or replaces the host's configured repositories.
- **`offline` validates the tarball against the running OS family** before installing, and
  fails early with a clear message instead of part-installing a foreign bundle.
- **Atomic save archive.** `offline-packages.tar.gz` is written under a temporary name and
  renamed only on success, so an interrupted `save` never leaves a truncated but
  valid-looking archive behind.
- **Argument handling.** `-h`/`--help` exits 0. Unknown `-flags` are rejected with an error
  instead of being silently treated as package names.
- **Staging hygiene.** Stale `offline-packages/` directories are removed (with a message) at
  the start of `save` and `offline` runs, and the extracted staging directory is cleaned up
  on exit.
- SLES/openSUSE: all zypper operations run non-interactively, and `save` uses a private
  package cache — the host's `/var/cache/zypp/packages` is never touched.

### Added
- **Behavior Notes** section in the README documenting the above, including the
  known SUSE limitation.
- `install_packages.sh` is now tracked executable (mode 755), so a fresh clone can run
  `sudo ./install_packages.sh` exactly as the README shows.

### Known limitation
- **SUSE `save` closure.** zypper has no `--alldeps` equivalent, so dependencies already
  installed on the build host are not bundled. For guaranteed air-gap closure, build SUSE
  save archives on a minimal/fresh host — the script prints this reminder on every SUSE `save`.

### Unchanged
- CLI surface (`online`, `offline`, `save`), the supported-distro list, and the
  `offline-packages.tar.gz` archive name/layout are all unchanged. Callers
  (`images-pull-push`, `harbor-registry-installer`, `seaweedfs-installer`,
  `technitium-dns-installer`, `automation-platform-tools`) need no changes.
