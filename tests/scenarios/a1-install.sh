#!/bin/bash
# A1, on a host with no route out: install jq and tree from the bundle the build role made.
set -uo pipefail
REPO=$PWD
fail=0
ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
# within <seconds> <command...>: true once the command is, checking every 3 seconds
within() { local t=$1 i; shift; for ((i = 0; i < t; i += 3)); do "$@" && return 0; sleep 3; done; "$@"; }
W=$(mktemp -d -p /var/tmp); cd "$W" || exit 1
cp "$REPO/install_packages.sh" .; chmod +x install_packages.sh
cp "$CI_HANDOFF/offline-packages.tar.gz" . && ok "put the bundle beside the script" || { bad "put the bundle beside the script"; echo "=== exit 1"; exit 1; }
for p in jq tree; do command -v "$p" >/dev/null && echo "  note: $p is already on this image"; done
./install_packages.sh offline jq tree > "$W/o" 2>&1 && ok "offline install with no route out" || { bad "offline install"; tail -8 "$W/o" | cut -c1-170; }
[ "$(echo '{"a":1}' | jq -c .a 2>/dev/null)" = 1 ] && ok "jq, from the bundle, runs" || bad "jq doesn't run"
tree -L 1 / >/dev/null 2>&1 && ok "tree, from the bundle, runs" || bad "tree doesn't run"
echo "=== exit $fail"; exit $fail
