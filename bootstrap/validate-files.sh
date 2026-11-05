#!/usr/bin/env bash
# Validates every file in bootstrap/files/ with the program that reads it on a host, using the
# bootstrap's own validators (host-files.sh). CI runs it in the host's Ubuntu release with the
# host's packages (.github/workflows/host-files.yml); it changes nothing outside a temp folder.
#
#   bootstrap/validate-files.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
HOST_FILES_DIR="$here/files"
# shellcheck source=bootstrap/host-files.sh
. "$here/host-files.sh"
# shellcheck source=/dev/null
. /etc/os-release
ADMIN_USER=ubuntu
UBUNTU_CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
failed=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failed=1; }

# HOST_FILES and files/ list the same paths: nothing installed is unvalidated, nothing is stray.
listed="$(printf '%s\n' "${HOST_FILES[@]}" | awk '{print $1}' | sort)"
present="$(cd "$HOST_FILES_DIR" && find . -type f | sed 's|^\./||' | sort)"
if [[ "$listed" == "$present" ]]; then
  pass "HOST_FILES lists exactly the files in bootstrap/files"
else
  fail "HOST_FILES and bootstrap/files differ: $(diff <(echo "$listed") <(echo "$present") | grep '^[<>]' | tr '\n' ' ')"
fi

for entry in "${HOST_FILES[@]}"; do
  read -r rel mode validator <<<"$entry"
  [[ -f "$HOST_FILES_DIR/$rel" ]] || continue
  candidate="$work/$(basename "$rel")"
  if ! render_host_file "$rel" >"$candidate"; then fail "$rel: placeholders"; continue; fi
  chmod "$mode" "$candidate"
  if [[ "$validator" == - ]]; then
    pass "$rel (no validator)"
  elif "$validator" "$candidate"; then
    pass "$rel ($validator)"
  else
    fail "$rel ($validator)"
  fi
done

# Each validator must also reject a known-bad file, so a validator that passes everything (a
# missing tool, classic sudo instead of the host's sudo-rs) cannot turn this job green.
# The sudoers case is the line that locked the admin out on 2026-11-05.
reject() {
  local validator="$1" name="$2" content="$3"
  printf '%s\n' "$content" >"$work/bad-$name"
  if "$validator" "$work/bad-$name" >/dev/null 2>&1; then
    fail "$validator accepted a bad file ($name)"
  else
    pass "$validator rejects a bad file ($name)"
  fi
}
reject validate_sudoers requiretty 'Defaults:deploy !requiretty'
reject validate_nft bad-policy 'table inet t { chain c { type filter hook input priority filter; policy maybe; } }'
reject validate_sshd unknown-option 'NoSuchOption yes'
reject validate_docker unknown-key '{ "no-such-key": true }'
reject validate_apt missing-semicolon 'APT::Periodic::Unattended-Upgrade "1"'

exit "$failed"
