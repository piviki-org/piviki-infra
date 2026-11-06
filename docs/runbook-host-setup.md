# Runbook: host setup (EC2, the test environment)

Performed by a founder, with the agent guiding. Every AWS rule here is AD-17's. Record the date,
who ran each step and any deviation in the story's Implementation Notes.

This host is the **test** environment (AD-17: test on AWS EC2; production starts later on OVH with
the same bootstrap, in `epic-soft-open`). Already run for test on 2026-11-05; kept for a rebuild.

Order across the two runbooks: this one §0 to §3, then `runbook-first-deploy.md` §1 (the
repositories and the first image), then §4 here (the bootstrap needs a `piviki-core` commit on
`main`), then `runbook-first-deploy.md` from §2.

## 0. Bitwarden (once, before the first secret exists)

The deploy key in §4 is the first secret, so this comes first (AD-17).

- [ ] Each founder creates their own account on **bitwarden.eu** (the EU region; an account
      cannot move between regions later) with a strong master password.
- [ ] Each founder turns on two-step login with an **authenticator app or a security key**, not
      email, and writes the **recovery code** down offline, with the master password, somewhere
      only they can reach.
- [ ] One founder creates a **free two-person organisation** `Piviki` and invites the other; both
      are **Owners**, so either can re-invite the other (Bitwarden cannot reset a lost master
      password).
- [ ] Collections: `production` and `test`. Every secret is a Login or Secure Note item named as
      in `secrets-inventory.md`, its value stored as text (the free plan has no attachments).
- [ ] The `age` backup private key is **not** stored in Bitwarden; it stays offline (AD-17).

## 1. AWS account (once)

- [ ] Account plan (Billing > Account plan): the free plan is acceptable for test (AD-17: it
      holds only test data the bootstrap and the import script can recreate). Record the plan's
      end date and kind of credits in the story notes; upgrade the account or move test before
      either runs out.
- [ ] Each founder signs in with their own IAM Identity Center or root-with-MFA login. No IAM
      user with access keys is created; nothing in Piviki uses AWS APIs.
- [ ] Region: an EU region (Stockholm `eu-north-1` is closest to Finland). All steps below are in
      that region.
- [ ] **EBS encryption by default**: EC2 > Settings > Data protection and security > EBS
      encryption > Always encrypt new EBS volumes: **enabled**.
- [ ] **SSM Default Host Management Configuration: off** (Systems Manager > Fleet Manager >
      Account management > Default Host Management Configuration: disabled).
- [ ] **IMDS defaults** (EC2 > Settings > Instance metadata defaults, optional but recommended):
      IMDSv2 required, hop limit 1, instance tags in metadata disabled.
- [ ] A monthly billing check is in both founders' calendars.

## 2. Security group

- [ ] Create `piviki-host`: inbound **only TCP 22**. Prefer the founders' current IP addresses;
      `0.0.0.0/0` is acceptable because sshd accepts keys only, but never 80, 443 or 5432.
      Outbound: all (the host pulls images and connects the Tunnel).

## 3. Launch the instance (EC2 > Launch instance)

| Setting | Value |
|---|---|
| Name | `piviki-test` (a Name tag only; renaming it later is harmless) |
| AMI | Ubuntu Server **LTS**, x86_64, from Canonical (owner `099720109477`). Use the latest LTS that OVH VPS-1 also offers; record the release (e.g. 24.04 or 26.04) here: `______` |
| Architecture | **x86_64** |
| Instance type | An x86_64 size no larger than OVH VPS-1 (confirm VPS-1's current specs first), e.g. `t3.small` or `t3.medium` |
| Key pair | A founder's ed25519 key (the admin user `ubuntu`) |
| Network | Default VPC, a public subnet, **auto-assign public IPv4: enabled** (GHCR has no IPv6) |
| Security group | `piviki-host` |
| Storage | One gp3 root volume, 30 GiB, **Encrypted: yes** (default KMS key) |
| Advanced > IAM instance profile | **None** |
| Advanced > Credit specification | **Standard** (not Unlimited) |
| Advanced > Metadata accessible | Enabled |
| Advanced > Metadata version | **V2 only (token required)** |
| Advanced > Metadata response hop limit | **1** |
| Advanced > Allow tags in metadata | Disabled |
| Advanced > Termination protection | Enabled |
| Advanced > User data | **Empty.** No secret, and no script, goes in user data. |

After launch, verify from the console (Instance > Actions > Instance settings / Modify instance
metadata options) and record:

- [ ] IAM role: none
- [ ] IMDSv2: required, hop limit: 1
- [ ] Credit specification: standard
- [ ] Root volume: encrypted
- [ ] Public IPv4 address: `______` (needed for the outside scan)

## 4. Bootstrap

Prerequisite: `runbook-first-deploy.md` §1 is done: `piviki-core` is on GitHub and `build` has
pushed the first image. Its tag is `<commit>-<date>`; the bootstrap places the host's
`piviki-core` checkout at that `<commit>` (AD-21).

On a founder's machine, create the deploy key. Store the private key in Bitwarden
(`test` collection, item `DEPLOY_SSH_KEY`, as in `secrets-inventory.md`); besides that it lives only in the
GitHub Environment:

```sh
ssh-keygen -t ed25519 -N '' -C piviki-test-deploy -f ./piviki-test-deploy
```

Copy `piviki-test-deploy.pub` to the host, then on the host:

```sh
ssh ubuntu@<public-ip>
sudo apt-get update && sudo apt-get install -y git
sudo git clone https://github.com/piviki-org/piviki-infra /opt/piviki/infra
sudo /opt/piviki/infra/bootstrap/bootstrap.sh --environment test \
     --core-commit <commit from the first tag> \
     --deploy-key ~/piviki-test-deploy.pub --admin-user ubuntu
rm ~/piviki-test-deploy.pub
```

Besides the host setup, this clones `piviki-core` root-owned to `/opt/piviki/core` at that
commit, points sudoers and the deploy user's forced command at
`/opt/piviki/core/deploy/deploy.sh`, links `/usr/local/sbin/piviki-compose` to the checkout,
and creates exactly the env files listed in `/opt/piviki/core/deploy/env-manifest`, empty.

Every config file it installs (firewall, sshd, sudoers, Docker, apt, journald) comes from
`bootstrap/files/`, at the same path. Change one there, by PR: the `host-files` workflow
validates it with the hosts' own programs before it can be merged, and the bootstrap validates it
again before it goes live. Never edit one on the host: `--check` reports a file that differs from
the repository, and the next bootstrap run puts the repository's version back.

The bootstrap is idempotent. It ends by running its checks; all must print `PASS`. Re-run the
checks at any time with `sudo /opt/piviki/infra/bootstrap/bootstrap.sh --check`.

Keep your current SSH session open and test a **new** SSH login before closing it (the bootstrap
turns off password and root login and limits `AllowUsers`).

Updating piviki-infra on a host later:

```sh
sudo git -C /opt/piviki/infra pull --ff-only
sudo /opt/piviki/infra/bootstrap/bootstrap.sh --environment test
```

Moving the `piviki-core` checkout (only a founder, only to a commit on `main`; AD-21). Needed
before deploying a tag whose `deploy/` differs from the checkout's, including a rollback; the
deploy refuses such a tag until then. It waits for no deploy to be running and leaves the running
stack alone:

```sh
sudo /opt/piviki/infra/bootstrap/bootstrap.sh --move-core <commit>
# if deploy/env-manifest gained a file or key, also re-run the full bootstrap and fill it:
sudo /opt/piviki/infra/bootstrap/bootstrap.sh --environment test
```

## 5. Hardening checks (record each result)

Run after the first deploy, and again after every bootstrap change.

### 5.1 Outside port scan

From a machine **outside AWS** (a founder's home connection, not the instance):

```sh
sudo nmap -Pn -sS -p- --min-rate 2000 <public-ip>
sudo nmap -Pn -sU --top-ports 50 <public-ip>
```

Expected: `22/tcp open ssh`, every other TCP port `filtered` or `closed`; no UDP port `open`.
Also confirm the security group and the host firewall are each enough on their own: temporarily
add `0.0.0.0/0` TCP 1-65535 to the security group, re-run the TCP scan (still only 22 open, the
host's nftables drops the rest), then remove the temporary rule.

### 5.2 Containers cannot reach the instance metadata service

```sh
# From core itself (AC: `docker compose exec core` fetching 169.254.169.254 fails):
sudo piviki-compose exec -T core node -e "fetch('http://169.254.169.254/latest/api/token',{method:'PUT',headers:{'X-aws-ec2-metadata-token-ttl-seconds':'60'},signal:AbortSignal.timeout(3000)}).then(r=>console.log('REACHABLE',r.status),e=>console.log('unreachable:',e.name))"
sudo piviki-compose exec -T core node -e "fetch('http://169.254.169.254/latest/meta-data/',{signal:AbortSignal.timeout(3000)}).then(r=>console.log('REACHABLE',r.status),e=>console.log('unreachable:',e.name))"
```

Expected: `unreachable: ...` for both. `bootstrap.sh --check` also runs the token probe from a
container on the non-internal `edge` network, which proves the hop limit itself (core's networks
have no route out at all).

From the host itself (not a container), IMDSv1 must be refused and no role attached:

```sh
curl -s -o /dev/null -w '%{http_code}\n' http://169.254.169.254/latest/meta-data/   # 401
```

### 5.3 Other checks

- [ ] `sudo ss -tlnp`: only sshd on a non-loopback address.
- [ ] `sudo nft list ruleset | grep -A3 'chain input'` in table `inet piviki_host`: `policy drop`.
- [ ] `systemctl is-enabled unattended-upgrades nftables docker`: all `enabled`.
- [ ] `sudo piviki-compose ps`: four services, no `PORTS` column entries.
- [ ] `sudo piviki-compose exec core id -u`: not `0`.
- [ ] `sudo docker inspect piviki-core-1 --format '{{.HostConfig.ReadonlyRootfs}}'`: `true`.
