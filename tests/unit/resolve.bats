#!/usr/bin/env bats
# Pin resolution, and the table of what happens to an installed package (spec 05, sections C and E).
load ../helpers
setup() {
  load_script install_packages.sh
  setup_stubs
  os_id=ubuntu
  stub apt-cache 'cat <<M
 docker-ce | 5:29.9.2-1~ubuntu.24.04~noble | https://x noble/stable amd64 Packages
 docker-ce | 5:29.9.0-1~ubuntu.24.04~noble | https://x noble/stable amd64 Packages
 docker-ce | 5:28.5.2-1~ubuntu.24.04~noble | https://x noble/stable amd64 Packages
 docker-ce | 5:28.5.1-1~ubuntu.24.04~noble | https://x noble/stable amd64 Packages
M'
  stub dpkg-query 'exit 1'
}
installed_apt() { stub dpkg-query "echo 'ii |$1'"; }

@test "a bare name passes through untouched" {
  PACKAGES_LIST=(curl jq)
  resolve_packages
  [ "${INSTALL_ARGS[*]}" = "curl jq" ]
  [ ${#PIN_RESULTS[@]} -eq 0 ]
}
@test "a short pin resolves to the newest build that matches" {
  PACKAGES_LIST=(docker-ce=28.5)
  resolve_packages
  [ "${INSTALL_ARGS[*]}" = "docker-ce=5:28.5.2-1~ubuntu.24.04~noble" ]
  [[ "${PIN_RESULTS[0]}" == docker-ce$'\t'28.5$'\t'5:28.5.2-* ]]
}
@test "a full apt string still works" {
  PACKAGES_LIST=(docker-ce=5:28.5.1-1~ubuntu.24.04~noble)
  resolve_packages
  [ "${INSTALL_ARGS[*]}" = "docker-ce=5:28.5.1-1~ubuntu.24.04~noble" ]
}
@test "an unknown version stops the run and lists what's available" {
  PACKAGES_LIST=(docker-ce=99)
  run resolve_packages
  [ "$status" -eq 1 ]
  [[ "$output" == *"no version of docker-ce matches '99'"* ]]
  [[ "$output" == *"5:29.9.2-1~ubuntu.24.04~noble"* ]]
}
@test "installed and matching the pin: does nothing" {
  installed_apt 5:28.5.1-1~ubuntu.24.04~noble
  PACKAGES_LIST=(docker-ce=28.5)
  resolve_packages
  [ ${#INSTALL_ARGS[@]} -eq 0 ]
  [ ${#DOWNGRADE_ARGS[@]} -eq 0 ]
}
@test "installed and older than the pin: upgrades to the pin" {
  installed_apt 5:28.5.1-1~ubuntu.24.04~noble
  PACKAGES_LIST=(docker-ce=29.9.0)
  resolve_packages
  [ "${INSTALL_ARGS[*]}" = "docker-ce=5:29.9.0-1~ubuntu.24.04~noble" ]
}
@test "installed and newer than the pin: refuses" {
  installed_apt 5:29.9.2-1~ubuntu.24.04~noble
  PACKAGES_LIST=(docker-ce=28.5)
  run resolve_packages
  [ "$status" -eq 1 ]
  [[ "$output" == *"--allow-downgrade"* ]]
}
@test "installed and newer than the pin, with --allow-downgrade: downgrades" {
  installed_apt 5:29.9.2-1~ubuntu.24.04~noble
  ALLOW_DOWNGRADE=1
  PACKAGES_LIST=(docker-ce=28.5)
  resolve_packages
  [ ${#INSTALL_ARGS[@]} -eq 0 ]
  [ "${DOWNGRADE_ARGS[*]}" = "docker-ce=5:28.5.2-1~ubuntu.24.04~noble" ]
}
@test "--no-upgrade keeps an installed bare name" {
  installed_apt 1.2.3
  NO_UPGRADE=1
  PACKAGES_LIST=(curl)
  resolve_packages
  [ ${#INSTALL_ARGS[@]} -eq 0 ]
}
@test "--no-upgrade still installs what's missing" {
  NO_UPGRADE=1
  PACKAGES_LIST=(curl)
  resolve_packages
  [ "${INSTALL_ARGS[*]}" = "curl" ]
}
@test "without --no-upgrade, an installed bare name goes through as today" {
  installed_apt 1.2.3
  PACKAGES_LIST=(curl)
  resolve_packages
  [ "${INSTALL_ARGS[*]}" = "curl" ]
}
@test "save ignores what's installed" {
  installed_apt 5:29.9.2-1~ubuntu.24.04~noble
  NO_UPGRADE=1
  PACKAGES_LIST=(docker-ce=28.5 curl)
  resolve_packages save
  [ "${INSTALL_ARGS[*]}" = "docker-ce=5:28.5.2-1~ubuntu.24.04~noble curl" ]
}
@test "dnf: resolves newest match, and spells it name-epoch:version-release" {
  os_id=rocky; rpm_pm=dnf
  stub dnf 'printf "0:7.76.1-40.el9\n\n0:7.76.1-40.el9_8.9\n0:7.76.1-40.el9_8.5\n"'
  stub rpm 'echo "package x is not installed"; exit 1'
  PACKAGES_LIST=(curl=7.76.1)
  resolve_packages
  [ "${INSTALL_ARGS[*]}" = "curl-0:7.76.1-40.el9_8.9" ]
}
@test "dnf: an exact version beats a longer build with the same start" {
  os_id=rocky; rpm_pm=dnf
  stub dnf 'printf "0:7.76.1-40.el9_8.9\n0:7.76.1-40.el9\n"'
  stub rpm 'echo "package x is not installed"; exit 1'
  PACKAGES_LIST=(curl=7.76.1-40.el9)
  resolve_packages
  [ "${INSTALL_ARGS[*]}" = "curl-0:7.76.1-40.el9" ]
}
@test "dnf: a name-version with no = passes straight through" {
  os_id=rocky; rpm_pm=dnf
  PACKAGES_LIST=(docker-ce-3:28.5.2-1.el9)
  resolve_packages
  [ "${INSTALL_ARGS[*]}" = "docker-ce-3:28.5.2-1.el9" ]
}
@test "dnf offline: the lookup is limited to the local repo" {
  os_id=rocky; rpm_pm=dnf; OFFLINE_SCOPE=1
  stub dnf 'echo "0:1.2-3.el9"'
  stub rpm 'echo "package x is not installed"; exit 1'
  PACKAGES_LIST=(foo=1.2)
  resolve_packages
  called '--disablerepo=* --enablerepo=offline-packages-repo'
}
@test "yum: a pin fails with a clear message" {
  os_id=rocky; rpm_pm=yum
  PACKAGES_LIST=(foo=1.2)
  run resolve_packages
  [ "$status" -eq 1 ]
  [[ "$output" == *"pins need dnf"* ]]
}
@test "zypper: resolves from the search output, and spells it name=edition" {
  os_id=opensuse-leap
  stub zypper "cat <<'X'
<solvable name=\"curl\" edition=\"8.6.0-150600.2.2\" arch=\"x86_64\"/>
<solvable name=\"curl\" edition=\"8.14.1-150600.4.40.1\" arch=\"x86_64\"/>
<solvable name=\"curl\" edition=\"8.14.1-150600.4.37.1\" arch=\"x86_64\"/>
X"
  stub rpm 'echo "package curl is not installed"; exit 1'
  PACKAGES_LIST=(curl=8.14.1)
  resolve_packages
  [ "${INSTALL_ARGS[*]}" = "curl=8.14.1-150600.4.40.1" ]
}
@test "zypper offline: the lookup is limited to the local repo" {
  os_id=sles; OFFLINE_SCOPE=1
  stub zypper 'echo "<solvable edition=\"1.2-3\"/>"'
  stub rpm 'echo "package x is not installed"; exit 1'
  PACKAGES_LIST=(foo=1.2)
  resolve_packages
  called '--repo offline-packages-repo'
}
