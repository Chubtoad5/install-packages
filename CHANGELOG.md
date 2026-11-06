# Changelog — install-packages

## v1.1.1 — 2026-11-06 — SUSE bundles hold the whole dependency set

### Fixed
- **`save` on SLES and openSUSE bundles what's already installed on the build host.** zypper only fetched
  dependencies this host didn't have yet, so a Docker bundle built on a host with Docker held 3 packages, and an
  offline install on a clean host failed with `nothing provides 'catatonit'`. `save` now resolves into an empty root
  that shares this host's repositories, so it fetches the full set, as the dnf and apt paths already did. The same
  bundle now holds 150 packages, about 142 MB, and installs offline on a clean Leap 16 host. The host's own RPM
  database and package cache are never touched.
  The root trusts the same signing keys as this host, so a host that checks each package's signature still saves.
- The note that `save` printed on every SUSE run, asking for a fresh host, is gone.

### Tests
- `tests/integration`: a Leap 16 case builds a Docker bundle on a host with Docker, then installs it on a clean
  container with every repo off. On a Leap host, the host itself builds the bundle. Both fail at v1.1.0.

No option, argument, exit code or archive layout changed.

## v1.1.0 — 2026-11-03 — Optional version pinning

Pinning is optional. A plain `install_packages.sh online curl` behaves exactly as before, so nothing needs to change
for anyone using this script on its own.

### Added
- **`name=version` on any supported distro.** It can be just the start of a version: `docker-ce=28.5.2` takes the
  newest 28.5.2 build, and `28.5` won't match `28.50`. An exact version wins over a longer build with the same start.
  A version that doesn't exist stops the run before anything is installed, and lists what's available.
- **Pins survive `save`.** The archive holds the pinned version, and `offline-packages/pins.lock` records what each
  pin resolved to. `offline` looks versions up in the bundle only. With no pins, no lock file is written.
- **`--no-upgrade`** keeps an installed package where it is, and still installs what's missing.
- **`--allow-downgrade`.** A pin older than the installed version refuses without it.
- **`--version`, and `SCRIPT_VERSION`.** `--version` and `--help` now work without root. The banner and each archive
  (`offline-packages/HELPER_VERSION`) record the version.
- **Tests:** `tests/unit`, `tests/contract` and `tests/integration`. Run the first two with `bats` from any clone.

### Changed
- A package argument with `=` now goes through version lookup instead of straight to `apt-get`. A full apt version
  string still works.

### Fixed
- Five `shellcheck` errors: arrays mixed into strings in the banner and progress messages.

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
