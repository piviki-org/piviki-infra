# shellcheck shell=bash
# The host's config files (bootstrap/files/<path> is installed at /<path>), shared by
# bootstrap.sh, which installs them, and validate-files.sh, which CI runs on every PR. Sourced,
# never run. The caller sets HOST_FILES_DIR, and ADMIN_USER and UBUNTU_CODENAME for the
# placeholders.

# Every file the bootstrap owns: <path under files/> <mode> <validator, or - for none>.
HOST_FILES=(
  "etc/apt/apt.conf.d/20auto-upgrades 0644 validate_apt"
  "etc/apt/apt.conf.d/52piviki-unattended-upgrades 0644 validate_apt"
  "etc/apt/sources.list.d/docker.sources 0644 -"
  "etc/docker/daemon.json 0644 validate_docker"
  "etc/systemd/journald.conf.d/50-piviki.conf 0644 -"
  "etc/nftables.conf 0755 validate_nft"
  "etc/ssh/sshd_config.d/10-piviki.conf 0644 validate_sshd"
  "etc/sudoers.d/piviki-deploy 0440 validate_sudoers"
)

# The entry for one path: "<mode> <validator>".
host_file_entry() {
  local entry
  for entry in "${HOST_FILES[@]}"; do
    [[ "${entry%% *}" == "$1" ]] && { printf '%s\n' "${entry#* }"; return 0; }
  done
  return 1
}

# A file as it belongs on this host: placeholders filled in. Values are checked first, because
# they go into sed and into root's config.
render_host_file() {
  [[ "$ADMIN_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo "bad admin user: $ADMIN_USER" >&2; return 1; }
  [[ "$UBUNTU_CODENAME" =~ ^[a-z]+$ ]] || { echo "bad Ubuntu codename: $UBUNTU_CODENAME" >&2; return 1; }
  local out
  out="$(sed -e "s/@ADMIN_USER@/$ADMIN_USER/g" -e "s/@UBUNTU_CODENAME@/$UBUNTU_CODENAME/g" "$HOST_FILES_DIR/$1")"
  if [[ "$out" =~ @[A-Z_]+@ ]]; then echo "$1: unfilled placeholder ${BASH_REMATCH[0]}" >&2; return 1; fi
  printf '%s\n' "$out"
}

# Validators: each checks one candidate file with the program that will read it, without
# applying it, and prints the program's error on failure.
validate_apt() { apt-config -c "$1" dump >/dev/null; }
validate_docker() {
  local out
  out="$(dockerd --validate --config-file "$1" 2>&1)" || { printf '%s\n' "$out" >&2; return 1; }
}
validate_nft() { nft -c -f "$1"; }
# The drop-in alone, as a whole config: catches unknown options and a bad Match block. The
# bootstrap also tests the full config after installing it.
validate_sshd() { sshd -t -f "$1"; }
validate_sudoers() { visudo -cf "$1" >/dev/null; }
