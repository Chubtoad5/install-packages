#!/bin/bash
# Real package managers, in real distro containers, on a throwaway host. Run as root, from the repo root.
set -uo pipefail
REPO=$PWD
export DEBIAN_FRONTEND=noninteractive
. /etc/os-release
# Docker to run the cases in, from wherever this distro gets it. Rocky's own repos don't have it.
case "$ID" in
  rocky)
    curl -fsSL https://download.docker.com/linux/rhel/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
    dnf install -y -q docker-ce >/dev/null 2>&1; systemctl enable --now docker >/dev/null 2>&1 ;;
  opensuse*)
    zypper -n -q install docker curl >/dev/null 2>&1; systemctl enable --now docker >/dev/null 2>&1 ;;
  *)
    apt-get update -qq && apt-get install -y -qq docker.io curl >/dev/null 2>&1 ;;
esac
docker version --format 'docker {{.Server.Version}}' || exit 1
CASES=$(mktemp -d)
OUT=$(mktemp -d)
chmod 755 "$CASES" "$OUT"
curl -fsSL https://raw.githubusercontent.com/Chubtoad5/install-packages/4bf03d6/install_packages.sh -o "$CASES/old_install_packages.sh" \
  && chmod +x "$CASES/old_install_packages.sh"

cat > "$CASES/lib.sh" <<'L'
fail=0
ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
expect() { local name=$1; shift; if "$@" >/tmp/out 2>&1; then ok "$name"; else bad "$name"; tail -5 /tmp/out | cut -c1-160; fi; }
refuse() { local name=$1; shift; if "$@" >/tmp/out 2>&1; then bad "$name"; else ok "$name"; fi; }
work() { mkdir -p /w && cd /w && cp /repo/install_packages.sh . && chmod +x install_packages.sh; }
L
cat > "$CASES/apt-repo.sh" <<'L'
apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null 2>&1
. /etc/os-release
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
apt-get update -qq
L
cat > "$CASES/apt.sh" <<'L'
source /cases/lib.sh; source /cases/apt-repo.sh; work
ver() { dpkg-query -W -f='${Version}' docker-ce-cli; }
FULL=$(apt-cache madison docker-ce-cli | sed -n 3p | awk '{print $3}')
NEWEST=$(apt-cache madison docker-ce-cli | sed -n 1p | awk '{print $3}')
SHORT=$(echo "${FULL#*:}" | cut -d- -f1)
echo "older=$FULL newest=$NEWEST short=$SHORT"
expect "short pin installs" ./install_packages.sh online "docker-ce-cli=$SHORT"
[ "$(ver)" = "$FULL" ] && ok "installed version is the pinned one" || bad "installed $(ver), wanted $FULL"
expect "re-run of the same pin is fine" ./install_packages.sh online "docker-ce-cli=$SHORT"
expect "--no-upgrade on a bare name" ./install_packages.sh online --no-upgrade docker-ce-cli
[ "$(ver)" = "$FULL" ] && ok "--no-upgrade kept the version" || bad "--no-upgrade moved it to $(ver)"
refuse "unknown version fails" ./install_packages.sh online docker-ce-cli=99.99
grep -q 'Available, newest first' /tmp/out && ok "the failure lists what's available" || bad "no list of versions"
expect "bare name without the flag still moves up, as today" ./install_packages.sh online docker-ce-cli
[ "$(ver)" = "$NEWEST" ] && ok "moved to newest" || bad "stayed at $(ver)"
refuse "a pin older than installed refuses" ./install_packages.sh online "docker-ce-cli=$SHORT"
[ "$(ver)" = "$NEWEST" ] && ok "the refusal changed nothing" || bad "the refusal moved it to $(ver)"
expect "--allow-downgrade moves back" ./install_packages.sh online --allow-downgrade "docker-ce-cli=$SHORT"
[ "$(ver)" = "$FULL" ] && ok "downgraded to the pin" || bad "at $(ver)"
expect "save with a pin" ./install_packages.sh save "docker-ce-cli=$SHORT"
tar -tzf offline-packages.tar.gz | grep -q "docker-ce-cli_.*$SHORT" && ok "archive holds the pinned version" || bad "archive holds: $(tar -tzf offline-packages.tar.gz | grep docker-ce-cli)"
tar -xzf offline-packages.tar.gz offline-packages/pins.lock -O | grep -q docker-ce-cli && ok "pins.lock written" || bad "no pins.lock"
cp offline-packages.tar.gz /out/pinned.tar.gz
exit $fail
L
cat > "$CASES/apt-offline.sh" <<'L'
source /cases/lib.sh; work
cp /out/pinned.tar.gz offline-packages.tar.gz
SHORT=$(tar -xzf offline-packages.tar.gz offline-packages/pins.lock -O | cut -f2)
expect "offline install from a pinned bundle, on a clean container" ./install_packages.sh offline "docker-ce-cli=$SHORT"
dpkg-query -W -f='${Version}\n' docker-ce-cli | grep -q "$SHORT" && ok "offline installed the pin" || bad "offline installed something else"
refuse "offline asking for a version not in the bundle fails" ./install_packages.sh offline docker-ce-cli=99.99
grep -q 'Available, newest first' /tmp/out && ok "and says what the bundle has" || bad "no list of versions"
ls /etc/apt/sources.list.d/*.bak 2>/dev/null | grep -q . && bad "apt sources left moved aside" || ok "apt sources restored"
exit $fail
L
cat > "$CASES/standalone.sh" <<'L'
source /cases/lib.sh; work
# A minimal Leap container has no tar, which this script assumes
command -v zypper >/dev/null && zypper -q --non-interactive install -y tar gzip >/dev/null 2>&1
expect "standalone: online, nothing but a name" ./install_packages.sh online jq
expect "standalone: save, nothing but a name" ./install_packages.sh save jq
tar -tzf offline-packages.tar.gz | grep -q pins.lock && bad "a lock file appeared with no pins" || ok "no lock file without pins"
expect "the old script's bundle still works with this script" sh -c '
  mkdir -p /old && cd /old && cp /cases/old_install_packages.sh ./install_packages.sh &&
  ./install_packages.sh save tree && mv offline-packages.tar.gz /w/offline-packages.tar.gz'
expect "and installs offline" ./install_packages.sh offline tree
command -v tree >/dev/null && ok "tree is installed" || bad "tree isn't installed"
exit $fail
L
cat > "$CASES/rpm.sh" <<'L'
source /cases/lib.sh; work
dnf -q -y install tar gzip >/dev/null 2>&1
ver() { rpm -q --qf '%{VERSION}-%{RELEASE}' tzdata; }
LIST=$(dnf -q repoquery --showduplicates --qf '%{version}-%{release}\n' tzdata | grep -v '^$' | sort -uV)
OLD=$(echo "$LIST" | head -1); NEW=$(echo "$LIST" | tail -1); echo "older=$OLD newest=$NEW"
rpm -e --nodeps tzdata >/dev/null 2>&1
expect "pin installs an older build" ./install_packages.sh online "tzdata=$OLD"
[ "$(ver)" = "$OLD" ] && ok "installed version is the pinned one" || bad "installed $(ver), wanted $OLD"
if [ "$OLD" != "$NEW" ]; then
  expect "--no-upgrade on a bare name" ./install_packages.sh online --no-upgrade tzdata
  [ "$(ver)" = "$OLD" ] && ok "--no-upgrade kept the version" || bad "--no-upgrade moved it to $(ver)"
  expect "bare name without the flag" ./install_packages.sh online tzdata
  echo "note: a bare re-run on dnf left tzdata at $(ver)"
  ./install_packages.sh online "tzdata=$NEW" >/dev/null 2>&1
  refuse "a pin older than installed refuses" ./install_packages.sh online "tzdata=$OLD"
  expect "--allow-downgrade moves back" ./install_packages.sh online --allow-downgrade "tzdata=$OLD"
  [ "$(ver)" = "$OLD" ] && ok "downgraded to the pin" || bad "at $(ver)"
fi
refuse "unknown version fails" ./install_packages.sh online tzdata=1999
expect "save with a pin" ./install_packages.sh save "tzdata=$OLD"
tar -tzf offline-packages.tar.gz | grep -q "tzdata-$OLD" && ok "archive holds the pinned version" || bad "archive holds: $(tar -tzf offline-packages.tar.gz | grep tzdata)"
cp offline-packages.tar.gz /out/pinned.tar.gz
echo "$OLD" > /out/pinned.ver
exit $fail
L
cat > "$CASES/rpm-offline.sh" <<'L'
source /cases/lib.sh; work
dnf -q -y install tar gzip >/dev/null 2>&1
cp /out/pinned.tar.gz offline-packages.tar.gz; OLD=$(cat /out/pinned.ver)
rpm -e --nodeps tzdata >/dev/null 2>&1
expect "offline install from a pinned bundle" ./install_packages.sh offline "tzdata=$OLD"
[ "$(rpm -q --qf '%{VERSION}-%{RELEASE}' tzdata)" = "$OLD" ] && ok "offline installed the pin" || bad "installed $(rpm -q tzdata)"
refuse "offline asking for a version not in the bundle fails" ./install_packages.sh offline tzdata=1999
[ -e /etc/yum.repos.d/offline-packages.repo ] && bad "local repo left behind" || ok "local repo removed"
exit $fail
L
cat > "$CASES/zypper.sh" <<'L'
source /cases/lib.sh; work
zypper -q --non-interactive install -y tar gzip >/dev/null 2>&1
zypper -q --non-interactive refresh >/dev/null 2>&1
ver() { rpm -q --qf '%{VERSION}-%{RELEASE}' timezone; }
LIST=$(zypper --xmlout --non-interactive search --details --match-exact --type package timezone | grep -o 'edition="[^"]*"' | cut -d'"' -f2 | sort -uV)
OLD=$(echo "$LIST" | head -1); NEW=$(echo "$LIST" | tail -1); echo "older=$OLD newest=$NEW"
rpm -e --nodeps timezone >/dev/null 2>&1
expect "pin installs an older build" ./install_packages.sh online "timezone=$OLD"
[ "$(ver)" = "$OLD" ] && ok "installed version is the pinned one" || bad "installed $(ver), wanted $OLD"
if [ "$OLD" != "$NEW" ]; then
  expect "--no-upgrade on a bare name" ./install_packages.sh online --no-upgrade timezone
  [ "$(ver)" = "$OLD" ] && ok "--no-upgrade kept the version" || bad "--no-upgrade moved it to $(ver)"
  expect "bare name without the flag" ./install_packages.sh online timezone
  echo "note: a bare re-run on zypper left timezone at $(ver)"
  ./install_packages.sh online "timezone=$NEW" >/dev/null 2>&1
  refuse "a pin older than installed refuses" ./install_packages.sh online "timezone=$OLD"
  expect "--allow-downgrade moves back" ./install_packages.sh online --allow-downgrade "timezone=$OLD"
  [ "$(ver)" = "$OLD" ] && ok "downgraded to the pin" || bad "at $(ver)"
fi
refuse "unknown version fails" ./install_packages.sh online timezone=1999
expect "save with a pin" ./install_packages.sh save "timezone=$OLD"
tar -tzf offline-packages.tar.gz | grep -q "timezone-$OLD" && ok "archive holds the pinned version" || bad "archive holds: $(tar -tzf offline-packages.tar.gz | grep timezone)"
cp offline-packages.tar.gz /out/pinned.tar.gz
echo "$OLD" > /out/pinned.ver
exit $fail
L
cat > "$CASES/zypper-offline.sh" <<'L'
source /cases/lib.sh; work
zypper -q --non-interactive install -y tar gzip >/dev/null 2>&1
cp /out/pinned.tar.gz offline-packages.tar.gz; OLD=$(cat /out/pinned.ver)
rpm -e --nodeps timezone >/dev/null 2>&1
expect "offline install from a pinned bundle" ./install_packages.sh offline "timezone=$OLD"
[ "$(rpm -q --qf '%{VERSION}-%{RELEASE}' timezone)" = "$OLD" ] && ok "offline installed the pin" || bad "installed $(rpm -q timezone)"
refuse "offline asking for a version not in the bundle fails" ./install_packages.sh offline timezone=1999
zypper lr offline-packages-repo >/dev/null 2>&1 && bad "local repo left behind" || ok "local repo removed"
exit $fail
L
# A bundle built where its packages are already installed. zypper used to skip what this host has, so a bundle for
# Docker built next to Docker left out catatonit and iptables, and couldn't install on a clean host.
cat > "$CASES/zypper-closure.sh" <<'L'
source /cases/lib.sh; work
zypper -q --non-interactive install -y tar gzip findutils docker >/dev/null 2>&1
rpm -q docker catatonit iptables >/dev/null && ok "this host already has docker, catatonit and iptables" || bad "docker didn't install here"
expect "save docker, with docker installed" ./install_packages.sh save docker docker-compose curl
for p in docker catatonit iptables containerd runc; do
  tar -tzf offline-packages.tar.gz | grep -q "/$p-[0-9]" && ok "bundle holds $p" || bad "bundle has no $p"
done
grep -q 'NOTE: zypper cannot bundle' /tmp/out && bad "still prints the old note" || ok "no note about missing dependencies"
rpm -q docker >/dev/null && ok "this host's docker is still installed" || bad "this host lost docker"
zypper lr 2>/dev/null | grep -q zypp-root && bad "a repo for the empty root was left behind" || ok "this host's repos are unchanged"
cp offline-packages.tar.gz /out/closure.tar.gz
exit $fail
L
cat > "$CASES/zypper-closure-offline.sh" <<'L'
source /cases/lib.sh; work
zypper -q --non-interactive install -y tar gzip findutils >/dev/null 2>&1
rpm -q docker >/dev/null 2>&1 && bad "this container shouldn't have docker yet" || ok "a clean host, with no docker"
# Turn every repo off, so nothing can come from anywhere but the bundle
zypper -q --non-interactive modifyservice --disable --all >/dev/null 2>&1; zypper -q --non-interactive modifyrepo --disable --all >/dev/null 2>&1
cp /out/closure.tar.gz offline-packages.tar.gz
expect "offline install of docker from that bundle" ./install_packages.sh offline docker docker-compose curl
rpm -q catatonit iptables >/dev/null && ok "catatonit and iptables came from the bundle" || bad "missing: $(rpm -q catatonit iptables | grep 'not installed')"
expect "docker runs" docker --version
exit $fail
L
rc=0
run() { # run <image> <case>
  echo "=== $1: $2"
  # z relabels the mounts for a host enforcing SELinux, and does nothing on one that isn't.
  docker run --rm -v "$REPO:/repo:ro,z" -v "$CASES:/cases:ro,z" -v "$OUT:/out:z" "$1" bash "/cases/$2.sh" || rc=1
}
run ubuntu:24.04 apt;       run ubuntu:24.04 apt-offline;  run ubuntu:24.04 standalone
run ubuntu:22.04 apt;       run ubuntu:22.04 apt-offline
run debian:12 apt;          run debian:12 apt-offline
run rockylinux:9 rpm;       run rockylinux:9 rpm-offline;  run rockylinux:9 standalone
run opensuse/leap:15.6 zypper; run opensuse/leap:15.6 zypper-offline; run opensuse/leap:15.6 standalone
run opensuse/leap:16.0 zypper-closure; run opensuse/leap:16.0 zypper-closure-offline
# The containers above are the same on every host. This is the real package manager on this host itself, so what a
# distro's run adds is this part. It's a throwaway clone, so a case may remove packages from it.
host_run() {
  echo "=== this host, $PRETTY_NAME: $1"
  ln -sfn "$REPO" /repo; ln -sfn "$CASES" /cases; ln -sfn "$OUT" /out
  bash "/cases/$1.sh" || rc=1
}
case "$ID" in
  rocky) host_run rpm; host_run rpm-offline; host_run standalone ;;
  # This host already has Docker, from the top of this file, so it builds the bundle for real and a clean container installs it.
  opensuse*) host_run zypper; host_run zypper-offline; host_run standalone; host_run zypper-closure; run opensuse/leap:16.0 zypper-closure-offline ;;
  *) host_run standalone ;;
esac
echo "=== exit $rc"
exit $rc
