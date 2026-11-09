#!/bin/bash
# A1, on a host with no route out: install jq and tree (and Docker on SUSE) from the bundle the build role made.
set -uo pipefail
REPO=$PWD
fail=0
ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
# within <seconds> <command...>: true once the command is, checking every 3 seconds
within() { local t=$1 i; shift; for ((i = 0; i < t; i += 3)); do "$@" && return 0; sleep 3; done; "$@"; }
W=$(mktemp -d -p /var/tmp); cd "$W" || exit 1
cp "$REPO/install_packages.sh" .; chmod +x install_packages.sh
# On SUSE, Docker too: it requires '(container-selinux if selinux-policy)', which only fires on an SELinux host (spec 15, F7).
. /etc/os-release
pkgs=(jq tree); [[ "$ID" =~ ^(sles|opensuse-leap)$ ]] && pkgs+=(docker)
cp "$CI_HANDOFF/offline-packages.tar.gz" . && ok "put the bundle beside the script" || { bad "put the bundle beside the script"; echo "=== exit 1"; exit 1; }
for p in "${pkgs[@]}"; do command -v "$p" >/dev/null && echo "  note: $p is already on this image"; done
./install_packages.sh offline "${pkgs[@]}" > "$W/o" 2>&1 && ok "offline install with no route out" || { bad "offline install"; tail -8 "$W/o" | cut -c1-170; echo "  (the checks after it would only fail too)"; echo "=== exit 1"; exit 1; }
[ "$(echo '{"a":1}' | jq -c .a 2>/dev/null)" = 1 ] && ok "jq, from the bundle, runs" || bad "jq doesn't run"
tree -L 1 / >/dev/null 2>&1 && ok "tree, from the bundle, runs" || bad "tree doesn't run"
if [[ " ${pkgs[*]} " == *" docker "* ]]; then
  if [ "$(getenforce 2>/dev/null)" = Enforcing ]; then
    rpm -q container-selinux >/dev/null && ok "SELinux is enforcing, and the bundle brought container-selinux" || bad "SELinux is enforcing, but container-selinux isn't installed"
  fi
  docker --version >/dev/null 2>&1 && ok "docker, from the bundle, runs" || bad "docker doesn't run"
fi
echo "=== exit $fail"; exit $fail
