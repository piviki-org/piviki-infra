#!/usr/bin/env bash
# One host setup (AD-17, AD-21): the only way a Piviki host is configured. Idempotent; re-run it
# after pulling a new piviki-infra revision.
#
#   sudo git clone https://github.com/piviki-org/piviki-infra /opt/piviki/infra
#   sudo /opt/piviki/infra/bootstrap/bootstrap.sh --environment production \
#        --core-commit <commit on piviki-core main> \
#        --deploy-key /root/deploy_ed25519.pub [--admin-user ubuntu]
#   sudo /opt/piviki/infra/bootstrap/bootstrap.sh --move-core <commit on piviki-core main>
#   sudo /opt/piviki/infra/bootstrap/bootstrap.sh --check
#
# It installs Docker from Docker's apt repository, blocks all inbound traffic except SSH on the
# host itself (nftables), turns on automatic security updates, hardens sshd, clones piviki-core
# root-owned to /opt/piviki/core at the named commit, creates the limited `deploy` user whose
# only command is that checkout's deploy/deploy.sh, and creates /etc/piviki (0700 root) with
# exactly the env files in the checkout's deploy/env-manifest, empty. It never writes a secret:
# a founder fills the env files from Bitwarden. --move-core moves the checkout to another commit
# on main (only a founder does this, never a deploy); it changes nothing else.
set -euo pipefail

INFRA_DIR=/opt/piviki/infra
CORE_DIR=/opt/piviki/core
CORE_REPO=https://github.com/piviki-org/piviki-core
DEPLOY_CMD="$CORE_DIR/deploy/deploy.sh"
MANIFEST="$CORE_DIR/deploy/env-manifest"
LOCK=/run/lock/piviki-deploy.lock
ETC_DIR=/etc/piviki
STATE_DIR=/var/lib/piviki
DEPLOY_USER=deploy

environment=""
deploy_key=""
admin_user="ubuntu"
core_commit=""
move_core=""
check_only=false

usage() {
  sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
}

while (($#)); do
  case "$1" in
    --environment) environment="${2:-}"; shift 2 ;;
    --deploy-key) deploy_key="${2:-}"; shift 2 ;;
    --admin-user) admin_user="${2:-}"; shift 2 ;;
    --core-commit) core_commit="${2:-}"; shift 2 ;;
    --move-core) move_core="${2:-}"; shift 2 ;;
    --check) check_only=true; shift ;;
    -h | --help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

log() { printf '\n== %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root"
# shellcheck source=/dev/null
. /etc/os-release
[[ "${ID:-}" == ubuntu ]] || die "Ubuntu LTS only (found ${ID:-unknown})"
[[ "$(uname -m)" == x86_64 ]] || die "x86_64 only"

core_git() { git -c safe.directory="$CORE_DIR" -C "$CORE_DIR" "$@"; }

# The manifest's entries: "<file> <KEY[=default]>..." per line, comments and blanks dropped, and
# the optional marker (`name?`) stripped: the bootstrap treats every listed file the same.
manifest_entries() { grep -Ev '^[[:space:]]*(#|$)' "$MANIFEST" | sed -E 's/^([^[:space:]]+)\?/\1/'; }

# Move (or first place) the checkout at a commit on piviki-core's main. Never a deploy's job.
# A first placement clones into a temporary folder beside it and moves it into place only once
# the commit is checked out, so a failed first run leaves no half-made checkout behind.
checkout_core() {
  local commit="$1" full dir="$CORE_DIR"
  [[ "$commit" =~ ^[0-9a-f]{12,40}$ ]] || die "core commit must be 12 to 40 hex characters"
  if [[ ! -d "$CORE_DIR/.git" ]]; then
    install -d -m 0755 -o root -g root "$(dirname "$CORE_DIR")"
    dir="$(mktemp -d "$(dirname "$CORE_DIR")/.core-clone.XXXXXX")"
    # Only the folder this run just created is removed, and only if placing it fails.
    trap 'rm -rf -- "$dir"' EXIT
    chmod 0755 "$dir"
    # --no-checkout: nothing is on disk until the named commit is checked out below.
    (umask 022 && git clone --quiet --no-checkout "$CORE_REPO" "$dir")
  else
    [[ -z "$(core_git status --porcelain --untracked-files=all)" ]] || die "$CORE_DIR has local changes; restore it before moving"
  fi
  local g=(git -c safe.directory="$dir" -C "$dir")
  (umask 022 && "${g[@]}" fetch --quiet origin main)
  full="$("${g[@]}" rev-parse --verify --quiet "${commit}^{commit}")" || die "commit $commit not found in $CORE_REPO"
  "${g[@]}" merge-base --is-ancestor "$full" origin/main || die "commit $commit is not on piviki-core main"
  (umask 022 && "${g[@]}" -c advice.detachedHead=false checkout --quiet --detach "$full")
  if [[ "$dir" != "$CORE_DIR" ]]; then
    mv -T "$dir" "$CORE_DIR"
    trap - EXIT
  fi
  echo "piviki-core checkout at $(core_git rev-parse --short=12 HEAD)"
}

# ---------------------------------------------------------------------------------------------
# Checks (also run at the end of every bootstrap)
# ---------------------------------------------------------------------------------------------
run_checks() {
  local failed=0
  ok() { printf 'PASS  %s\n' "$1"; }
  bad() { printf 'FAIL  %s\n' "$1"; failed=1; }

  log "host checks"
  if nft list table inet piviki_host >/dev/null 2>&1; then ok "nftables table inet piviki_host loaded"; else bad "nftables table missing"; fi
  # Never `cmd | grep -q` under pipefail: grep exits at the first match, cmd dies of SIGPIPE
  # (141) and the pipeline reports failure for a match. Capture the output, then match it.
  if [[ "$(nft list chain inet piviki_host input 2>/dev/null)" == *"policy drop"* ]]; then ok "inbound policy drop"; else bad "inbound policy is not drop"; fi

  local listening
  listening="$(ss -Htlnp 2>/dev/null | awk '{print $4}' | grep -Ev '^(127\.|\[::1\]|\[::ffff:127\.)' | grep -Ev ':22$' || true)"
  if [[ -z "$listening" ]]; then ok "no non-loopback TCP listener except :22"; else bad "unexpected listeners: $(tr '\n' ' ' <<<"$listening")"; fi

  if [[ "$(sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2}')" == no ]]; then ok "sshd: password authentication off"; else bad "sshd: password authentication on"; fi
  if [[ "$(sshd -T 2>/dev/null | awk '/^permitrootlogin /{print $2}')" == no ]]; then ok "sshd: root login off"; else bad "sshd: root login allowed"; fi

  if [[ " $(id -nG "$DEPLOY_USER" 2>/dev/null) " == *" docker "* ]]; then bad "deploy user is in the docker group"; else ok "deploy user not in docker group"; fi

  # AD-21: the piviki-core checkout is root-owned, writable by root only, and clean; sudoers and
  # sshd name its deploy script, not a copy.
  if [[ -d "$CORE_DIR/.git" ]]; then
    local writable
    writable="$(find "$(dirname "$CORE_DIR")" ! -type l \( ! -user root -o -perm /022 \) -print -quit 2>/dev/null)"
    if [[ -z "$writable" ]]; then ok "$CORE_DIR is root-owned and writable by root only"; else bad "$CORE_DIR: $writable is not root-only"; fi
    if [[ -z "$(core_git status --porcelain --untracked-files=all 2>/dev/null)" ]]; then ok "core checkout clean at $(core_git rev-parse --short=12 HEAD)"; else bad "core checkout has local changes"; fi
    if [[ -x "$DEPLOY_CMD" ]]; then ok "deploy script present: $DEPLOY_CMD"; else bad "$DEPLOY_CMD missing or not executable"; fi
    if grep -qF "NOPASSWD: $DEPLOY_CMD" /etc/sudoers.d/piviki-deploy 2>/dev/null; then ok "sudoers names the checkout's deploy script"; else bad "sudoers does not name $DEPLOY_CMD"; fi
  else
    bad "no piviki-core checkout at $CORE_DIR"
  fi

  if [[ "$(stat -c '%a %U' "$ETC_DIR" 2>/dev/null)" == "700 root" ]]; then ok "$ETC_DIR is 0700 root"; else bad "$ETC_DIR is not 0700 root"; fi
  if [[ -r "$MANIFEST" ]]; then
    local name keys key extra=""
    while read -r name keys; do
      [[ -e "$ETC_DIR/$name" ]] || { bad "$name (env-manifest) missing"; continue; }
      for key in $keys; do
        grep -q "^${key%%=*}=" "$ETC_DIR/$name" || bad "$name has no ${key%%=*}= line"
      done
    done < <(manifest_entries)
    for f in "$ETC_DIR"/*.env; do
      [[ -e "$f" ]] || continue
      grep -qx "$(basename "$f")" <<<"$(manifest_entries | awk '{print $1}')" || extra+="$(basename "$f") "
    done
    if [[ -z "$extra" ]]; then ok "env files match env-manifest"; else bad "env files not in env-manifest: $extra"; fi
  fi
  local f
  for f in "$ETC_DIR"/*.env; do
    [[ -e "$f" ]] || continue
    if [[ "$(stat -c '%a %U' "$f")" == "600 root" ]]; then ok "$(basename "$f") is 0600 root"; else bad "$(basename "$f") is not 0600 root"; fi
  done

  if grep -q 'APT::Periodic::Unattended-Upgrade "1"' <<<"$(apt-config dump 2>/dev/null)"; then ok "unattended upgrades on"; else bad "unattended upgrades off"; fi
  if snap list amazon-ssm-agent >/dev/null 2>&1; then bad "amazon-ssm-agent is installed"; else ok "no SSM agent"; fi

  # AWS only: IMDSv2 required (an IMDSv1 request is refused) and no instance role attached.
  if [[ "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" == "Amazon EC2" ]]; then
    local v1 token iam
    v1="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://169.254.169.254/latest/meta-data/ || true)"
    if [[ "$v1" == 401 ]]; then ok "IMDSv1 refused (401)"; else bad "IMDSv1 answered $v1, want 401"; fi
    token="$(curl -s --max-time 3 -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' || true)"
    iam="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/iam/security-credentials/ || true)"
    if [[ "$iam" == 404 ]]; then ok "no IAM role on the instance"; else bad "IAM credentials endpoint answered $iam, want 404"; fi
    # The hop limit of 1 is what keeps containers out. Check from core itself and from a container
    # on the non-internal `edge` network, using the running core image's node (AD-17).
    local tag probe
    tag="$(sed -n 's/^CORE_TAG=//p' "$STATE_DIR/compose.env" 2>/dev/null || true)"
    probe="fetch('http://169.254.169.254/latest/api/token',{method:'PUT',headers:{'X-aws-ec2-metadata-token-ttl-seconds':'60'},signal:AbortSignal.timeout(3000)}).then(r=>{console.log('reachable',r.status);process.exit(1)},()=>process.exit(0))"
    if [[ -n "$tag" ]] && docker network inspect piviki_edge >/dev/null 2>&1; then
      if /usr/local/sbin/piviki-compose exec -T core node -e "$probe" >/dev/null 2>&1; then
        ok "core cannot reach IMDS"
      else
        bad "core reached IMDS"
      fi
      if docker run --rm --network piviki_edge --entrypoint node "ghcr.io/piviki-org/piviki-core:$tag" \
        -e "$probe" >/dev/null 2>&1; then
        ok "a container on the edge network cannot reach IMDS"
      else
        bad "a container obtained an IMDS token (hop limit must be 1)"
      fi
    else
      echo "SKIP  container IMDS checks (no deploy yet)"
    fi
  fi

  return "$failed"
}

if $check_only; then
  run_checks
  exit $?
fi

if [[ -n "$move_core" ]]; then
  [[ -d "$CORE_DIR/.git" ]] || die "no checkout at $CORE_DIR yet; run the full bootstrap with --core-commit"
  # The same lock as deploy.sh: the checkout never moves during a deploy.
  exec 9>"$LOCK"
  flock -n 9 || die "a deploy is running; try again when it ends"
  checkout_core "$move_core"
  echo "The running stack is unchanged. Next deploy: a tag whose commit has this deploy/ (AD-21)."
  run_checks || die "host checks failed"
  exit 0
fi

[[ "$environment" == production || "$environment" == test ]] || die "--environment production|test is required"
if [[ -s "$ETC_DIR/environment" && "$(cat "$ETC_DIR/environment")" != "$environment" ]]; then
  die "this host is '$(cat "$ETC_DIR/environment")'; refusing to switch it to '$environment'. Repurposing a host is a deliberate step: a founder changes $ETC_DIR/environment by hand first."
fi
if [[ -d "$CORE_DIR/.git" ]]; then
  [[ -z "$core_commit" || "$(core_git rev-parse --verify --quiet "${core_commit}^{commit}")" == "$(core_git rev-parse HEAD)" ]] ||
    die "the core checkout is already placed; move it with --move-core, not --core-commit"
else
  [[ -n "$core_commit" ]] || die "--core-commit <commit on piviki-core main> is required on the first run"
fi
[[ "$(cd "$(dirname "$0")/.." && pwd -P)" == "$INFRA_DIR" ]] || die "run from the checkout at $INFRA_DIR"
id "$admin_user" >/dev/null 2>&1 || die "admin user $admin_user does not exist"
[[ -s "/home/$admin_user/.ssh/authorized_keys" ]] || die "$admin_user has no SSH key; refusing to restrict sshd"

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------------------------
log "packages"
apt-get update -q
apt-get install -y -q ca-certificates curl gnupg git jq nftables unattended-upgrades apt-listchanges

# ---------------------------------------------------------------------------------------------
log "piviki-core checkout (AD-21)"
if [[ -d "$CORE_DIR/.git" ]]; then
  echo "piviki-core checkout at $(core_git rev-parse --short=12 HEAD) (unchanged; --move-core moves it)"
else
  checkout_core "$core_commit"
fi
[[ -x "$DEPLOY_CMD" && -r "$MANIFEST" ]] || die "the checkout has no deploy/deploy.sh or deploy/env-manifest"

# Only EC2 (the instance's own services) and its disk are used (AD-17): no SSM agent.
if snap list amazon-ssm-agent >/dev/null 2>&1; then
  snap remove --purge amazon-ssm-agent
fi

# ---------------------------------------------------------------------------------------------
log "automatic security updates"
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
cat >/etc/apt/apt.conf.d/52piviki-unattended-upgrades <<'EOF'
// Security updates install daily; the host reboots for them at 03:30 UTC when required.
// Every service has restart: unless-stopped, so the stack returns after a reboot.
Unattended-Upgrade::Origins-Pattern {
        "origin=Ubuntu,archive=${distro_codename}-security";
        "origin=UbuntuESMApps,archive=${distro_codename}-apps-security";
        "origin=UbuntuESM,archive=${distro_codename}-infra-security";
        "origin=Docker,label=Docker CE";
};
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:30";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
systemctl enable --now unattended-upgrades.service >/dev/null

# ---------------------------------------------------------------------------------------------
log "docker"
install -m 0755 -d /etc/apt/keyrings
if [[ ! -s /etc/apt/keyrings/docker.asc ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
fi
cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update -q
apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

install -d -m 0755 /etc/docker
cat >/etc/docker/daemon.json <<'EOF'
{
  "log-driver": "local",
  "log-opts": { "max-size": "20m", "max-file": "10" },
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true
}
EOF
systemctl enable docker >/dev/null
systemctl restart docker

# Host logs rotate at about 30 days (AD-14).
install -d -m 0755 /etc/systemd/journald.conf.d
cat >/etc/systemd/journald.conf.d/50-piviki.conf <<'EOF'
[Journal]
MaxRetentionSec=30day
EOF
systemctl restart systemd-journald

# ---------------------------------------------------------------------------------------------
log "firewall: inbound SSH only"
# A table of our own, never `flush ruleset`, so Docker's own rules are left alone. Published
# container ports would bypass this chain through DNAT/forward, which is why Compose publishes none.
cat >/etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
# Managed by piviki-infra bootstrap. Inbound: SSH only, on the host itself (AD-17).
table inet piviki_host
delete table inet piviki_host

table inet piviki_host {
	chain input {
		type filter hook input priority filter; policy drop;
		iif "lo" accept
		ct state established,related accept
		ct state invalid drop
		meta l4proto icmp icmp type { echo-request, destination-unreachable, time-exceeded } limit rate 10/second accept
		meta l4proto ipv6-icmp accept
		udp sport 67 udp dport 68 accept comment "DHCPv4 replies"
		udp sport 547 udp dport 546 accept comment "DHCPv6 replies"
		iifname "br-*" tcp dport 22 accept comment "Tunnel SSH from cloudflared (docker bridges), not rate-limited"
		tcp dport 22 ct state new limit rate 30/minute accept comment "SSH by key"
	}
}
EOF
nft -c -f /etc/nftables.conf
systemctl enable nftables >/dev/null
# Never `restart`: Ubuntu's nftables.service stops with `nft flush ruleset`, which would wipe
# Docker's rules. Reload (or first start) only re-reads this file, which replaces our own table.
if systemctl is-active --quiet nftables; then systemctl reload nftables; else systemctl start nftables; fi

# ---------------------------------------------------------------------------------------------
log "sshd"
cat >/etc/ssh/sshd_config.d/10-piviki.conf <<EOF
# Managed by piviki-infra bootstrap.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AllowUsers ${admin_user} ${DEPLOY_USER}
X11Forwarding no
AllowAgentForwarding no
MaxAuthTries 3
LoginGraceTime 30

Match User ${DEPLOY_USER}
	AllowTcpForwarding no
	PermitTTY no
	ForceCommand sudo -n ${DEPLOY_CMD} "\$SSH_ORIGINAL_COMMAND"
EOF
sshd -t
systemctl reload ssh 2>/dev/null || systemctl reload sshd

# ---------------------------------------------------------------------------------------------
log "deploy user"
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /var/lib/piviki-deploy --shell /bin/sh "$DEPLOY_USER"
fi
passwd -l "$DEPLOY_USER" >/dev/null
gpasswd -d "$DEPLOY_USER" docker >/dev/null 2>&1 || true
install -d -m 0700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" /var/lib/piviki-deploy/.ssh
if [[ -n "$deploy_key" ]]; then
  [[ -s "$deploy_key" ]] || die "deploy key file $deploy_key is empty or missing"
  grep -Eq '^(ssh-ed25519|ecdsa-sha2-nistp256) ' "$deploy_key" || die "deploy key must be one ed25519/ecdsa public key"
  key="$(grep -Em1 '^(ssh-ed25519|ecdsa-sha2-nistp256) ' "$deploy_key")"
  printf 'restrict %s\n' "$key" >/var/lib/piviki-deploy/.ssh/authorized_keys
  chown "$DEPLOY_USER:$DEPLOY_USER" /var/lib/piviki-deploy/.ssh/authorized_keys
  chmod 0600 /var/lib/piviki-deploy/.ssh/authorized_keys
elif [[ ! -s /var/lib/piviki-deploy/.ssh/authorized_keys ]]; then
  echo "note: no --deploy-key given and none installed yet; deploys will be refused until one is"
fi

# The checkout's own files, never copies (AD-21): moving the checkout moves these with it.
ln -sfn "$CORE_DIR/deploy/piviki-compose" /usr/local/sbin/piviki-compose
# Only a rule, no Defaults: Ubuntu's sudo-rs rejects requiretty as unknown and does not list
# env_reset, and both are already what we need: no tty is required, and the environment is
# always reset, so the deploy script's PIVIKI_* test overrides never reach it for real.
# Validated before it is put in place: a broken file in /etc/sudoers.d can break sudo.
sudoers_tmp="$(mktemp /etc/sudoers.d/.piviki-deploy.XXXXXX)"
cat >"$sudoers_tmp" <<EOF
# The deploy user may run exactly one program as root, from the root-owned piviki-core
# checkout (AD-21); it validates its own arguments.
${DEPLOY_USER} ALL=(root) NOPASSWD: ${DEPLOY_CMD}
EOF
chmod 0440 "$sudoers_tmp"
visudo -cf "$sudoers_tmp" >/dev/null || { rm -f "$sudoers_tmp"; die "sudoers rule failed validation"; }
mv -f "$sudoers_tmp" /etc/sudoers.d/piviki-deploy

# ---------------------------------------------------------------------------------------------
log "configuration and state directories"
install -d -m 0700 -o root -g root "$ETC_DIR"
install -d -m 0755 -o root -g root "$STATE_DIR"
printf '%s\n' "$environment" >"$ETC_DIR/environment"
chmod 0600 "$ETC_DIR/environment"

# Exactly the env files in the checkout's deploy/env-manifest; each service reads only its own
# (docs/secrets-inventory.md). A key the manifest gained is appended empty; values are never
# touched. A file not in the manifest fails the checks below; a founder removes it.
while read -r name keys; do
  [[ "$name" =~ ^[a-z0-9-]+\.env$ ]] || die "bad env-manifest file name: $name"
  (umask 077 && touch "$ETC_DIR/$name")
  for key in $keys; do
    [[ "$key" == *=* ]] || key="$key="
    grep -q "^${key%%=*}=" "$ETC_DIR/$name" || printf '%s\n' "$key" >>"$ETC_DIR/$name"
  done
  chown root:root "$ETC_DIR/$name"
  chmod 0600 "$ETC_DIR/$name"
done < <(manifest_entries)

# ---------------------------------------------------------------------------------------------
run_checks || die "host checks failed"
log "bootstrap complete for environment: $environment"
echo "Next: fill the env files in $ETC_DIR (docs/runbook-first-deploy.md)."
