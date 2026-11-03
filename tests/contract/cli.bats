#!/usr/bin/env bats
# What every consumer relies on: modes, positional package names, the tarball's name and layout, exit codes.
load ../helpers
SCRIPT="$BATS_TEST_DIRNAME/../../install_packages.sh"
setup() {
  setup_stubs
  cd "$STUB_DIR"
  stub apt-get 'if [[ "$1" == download ]]; then shift; for p in "$@"; do [[ "$p" == -* ]] || touch "${p%%=*}_1.0_amd64.deb"; done; fi'
  stub dpkg-scanpackages 'exit 0'
  stub apt-cache 'if [[ "$1" == depends ]]; then echo curl; echo libfoo; else cat <<M
 curl | 8.5.0-2 | https://x Packages
 curl | 8.4.0-1 | https://x Packages
M
fi'
}
@test "--version needs no root, and prints a version" {
  run su -s /bin/bash nobody -c "bash '$SCRIPT' --version"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}
@test "--help needs no root" {
  run su -s /bin/bash nobody -c "bash '$SCRIPT' --help"
  [ "$status" -eq 0 ]
  [[ "$output" == *"online"* && "$output" == *"offline"* && "$output" == *"save"* ]]
}
@test "needs root for real work" {
  run su -s /bin/bash nobody -c "bash '$SCRIPT' online curl"
  [ "$status" -ne 0 ]
}
@test "an unknown flag is an error" {
  run "$SCRIPT" online --nope curl
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option"* ]]
}
@test "no mode is an error" {
  run "$SCRIPT" curl
  [ "$status" -ne 0 ]
}
@test "no packages is an error" {
  run "$SCRIPT" online
  [ "$status" -ne 0 ]
}
@test "a plain call sends the bare names to the package manager, as consumers expect" {
  run "$SCRIPT" online curl jq
  [ "$status" -eq 0 ]
  called 'apt-get install -y -qq curl jq'
}
@test "offline without the tarball is an error" {
  run "$SCRIPT" offline curl
  [ "$status" -ne 0 ]
  [[ "$output" == *"Tarball not found"* ]]
}
@test "save writes offline-packages.tar.gz, with the layout offline expects, and no lock file without pins" {
  run "$SCRIPT" save curl
  [ "$status" -eq 0 ]
  [ -s offline-packages.tar.gz ]
  tar -tzf offline-packages.tar.gz | grep -qx 'offline-packages/curl_1.0_amd64.deb'
  tar -tzf offline-packages.tar.gz | grep -qx 'offline-packages/HELPER_VERSION'
  ! tar -tzf offline-packages.tar.gz | grep -q pins.lock
  [ ! -d offline-packages ]
}
@test "save with a pin downloads the pinned version and records it" {
  run "$SCRIPT" save curl=8.4
  [ "$status" -eq 0 ]
  called 'apt-get download -qq curl=8.4.0-1 libfoo'
  tar -xzf offline-packages.tar.gz offline-packages/pins.lock -O | grep -q $'curl\t8.4\t8.4.0-1'
}
