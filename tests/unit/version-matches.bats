#!/usr/bin/env bats
load ../helpers
setup() { load_script install_packages.sh; }

@test "a prefix ending at a boundary matches" {
  version_matches 28.5.2 5:28.5.2-1~ubuntu.24.04~noble
  version_matches 28.5 5:28.5.2-1~ubuntu.24.04~noble
  version_matches 28 5:28.5.2-1~ubuntu.24.04~noble
  version_matches 7.76.1 0:7.76.1-40.el9
  version_matches 8.14.1-150600.4.40.1 8.14.1-150600.4.40.1
}
@test "the whole string, with or without its epoch, matches" {
  version_matches 5:28.5.2-1~ubuntu.24.04~noble 5:28.5.2-1~ubuntu.24.04~noble
  version_matches 28.5.2-1~ubuntu.24.04~noble 5:28.5.2-1~ubuntu.24.04~noble
}
@test "a prefix stopping mid-number or mid-word doesn't match" {
  ! version_matches 28.5 5:28.50.1-1
  ! version_matches 2 5:28.5.2-1
  ! version_matches 28.5.2-1 5:28.5.2-10
  ! version_matches 1.2 1.2a-1
}
@test "a different version doesn't match" {
  ! version_matches 29 5:28.5.2-1
  ! version_matches 28.6 5:28.5.2-1
}
