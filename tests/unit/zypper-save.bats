#!/usr/bin/env bats
# A SUSE save resolves in an empty root, so conditional requirements "(A if B)" never fire there (spec 15, F7).
load ../helpers
setup() {
  load_script install_packages.sh
  setup_stubs
  RPMS=$(mktemp -d); touch "$RPMS/docker.rpm"
  stub rpm 'case "$*" in
  "-qp --requires"*) printf "%s\n" "(container-selinux if selinux-policy)" "(foo-tools if foo)" "containerd >= 1.7.3" "(a or b)" "(x if y else z)" ;;
  "-q --whatprovides selinux-policy") exit 0 ;;
  *) exit 1 ;;
esac'
}
@test "an A whose B this host has is added" {
  run zypper_conditional_extras "$RPMS"
  [ "$status" -eq 0 ]
  [ "$output" = container-selinux ]
}
@test "an A whose B this host doesn't have, and other rich forms, are left out" {
  stub rpm 'case "$*" in
  "-qp --requires"*) printf "%s\n" "(foo-tools if foo)" "containerd >= 1.7.3" "(a or b)" "(x if y else z)" ;;
  "-q --whatprovides y") exit 0 ;;
  *) exit 1 ;;
esac'
  run zypper_conditional_extras "$RPMS"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
@test "no rpms, nothing added" {
  run zypper_conditional_extras "$(mktemp -d)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
