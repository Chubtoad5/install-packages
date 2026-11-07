#!/usr/bin/env bats
# Spec 11, U1: apt runs with -qq, which hid why an install failed. A failure now shows the lines that name the package.
load ../helpers
setup() {
  load_script install_packages.sh
  setup_stubs
  os_id=ubuntu
  stub dpkg-query 'exit 1'
  stub apt-cache 'exit 0'
}
# apt-get that fails a real install the way apt 2.7 did on Ubuntu 24.04.4, and explains itself only in a dry run
apt_fails() {
  stub apt-get 'case " $* " in
  *" update "*) exit 0 ;;
  *" -s "*) cat <<M
Reading package lists...
Building dependency tree...
Reading state information...
Some packages could not be installed. This may mean that you have
requested an impossible situation or if you are using the unstable
distribution that some required packages have not yet been created
or been moved out of Incoming.
The following information may help to resolve the situation:

The following packages have unmet dependencies:
 curl : Depends: libcurl4t64 (= 8.5.0-2ubuntu10.16) but 8.5.0-2ubuntu10.8 is to be installed
E: Unable to correct problems, you have held broken packages.
M
    exit 100 ;;
  *) echo "E: Unmet dependencies. Try '"'"'apt --fix-broken install'"'"' with no packages (or specify a solution)." >&2; exit 100 ;;
esac'
}

@test "a failed apt install names the unmet dependency" {
  apt_fails
  PACKAGES_LIST=(curl)
  run apt_install_packages
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: apt-get install failed."* ]]
  [[ "$output" == *"curl : Depends: libcurl4t64 (= 8.5.0-2ubuntu10.16) but 8.5.0-2ubuntu10.8 is to be installed"* ]]
  [[ "$output" == *"E: Unable to correct problems"* ]]
}
@test "the explanation is a dry run of the same request" {
  apt_fails
  PACKAGES_LIST=(curl jq)
  run apt_install_packages
  called "apt-get install -s curl jq"
}
@test "a failed downgrade is explained too, with the downgrade allowed" {
  apt_fails
  DOWNGRADE_ARGS=(docker-ce=5:28.5.1-1~ubuntu.24.04~noble)
  run apt_explain_failure --allow-downgrades "${DOWNGRADE_ARGS[@]}"
  called "apt-get install -s --allow-downgrades docker-ce=5:28.5.1-1~ubuntu.24.04~noble"
  [[ "$output" == *"curl : Depends: libcurl4t64"* ]]
}
@test "apt 3's wording is found too" {
  stub apt-get 'printf "%s\n" "Solving dependencies... Error!" "Unsatisfied dependencies:" " curl : Depends: libcurl4t64 (= 8.14.1-1) but 8.12.0-1 is to be installed" "Error: Unable to satisfy dependencies. Reached two conflicting decisions:"; exit 100'
  run apt_explain_failure curl
  [[ "$output" == *"curl : Depends: libcurl4t64 (= 8.14.1-1)"* ]]
  [[ "$output" == *"Error: Unable to satisfy dependencies"* ]]
}
@test "with no dependency listing, apt's error lines are shown" {
  stub apt-get 'echo "E: Unable to locate package nosuchpkg"; exit 100'
  run apt_explain_failure nosuchpkg
  [[ "$output" == *"E: Unable to locate package nosuchpkg"* ]]
}
@test "a dry run that says nothing adds nothing, and doesn't end the run" {
  stub apt-get 'exit 100'
  run apt_explain_failure curl
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
@test "with errexit on, as the script runs, a silent dry run still returns" {
  stub apt-get 'exit 100'
  run bash -c 'set -e; source "$1"; set -e; apt_explain_failure curl; echo returned' _ "$BATS_TEST_DIRNAME/../../install_packages.sh"
  [[ "$output" == *returned* ]]
}
