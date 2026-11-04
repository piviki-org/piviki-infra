# Runbook: first deploy to production (story 1.1)

The order matters (AD-5): the first librarian is seeded over SSH **before** the `admin` and `api`
DNS records exist. A founder performs every console step; the agent guides. Record each step's
date, who ran it and any output asked for in the story's Implementation Notes.

Order: `runbook-host-setup.md` §0 to §3, then §1 here, then `runbook-host-setup.md` §4 (the
bootstrap places the host's `piviki-core` checkout at the first image's commit), then §2 on here.

## 1. GitHub organisation and repositories

- [ ] Organisation `piviki-org` exists; both founders are owners with MFA required
      (Settings > Authentication security > Require two-factor authentication).
- [ ] Repositories `piviki-org/piviki-core` and `piviki-org/piviki-infra`, **public**, MIT,
      default branch `main`. Before the first push, check both for personal details and the
      pickup address (AD-18).
- [ ] In **each** repository, Settings > Advanced Security: Dependabot alerts **on**, Dependabot
      security updates **on**, Secret scanning **on**, Push protection **on**.
- [ ] Team `piviki-org/admins` with both founders (Org > Teams), named in
      `piviki-core/.github/CODEOWNERS`. In `piviki-core`, a ruleset on `main`: require a pull
      request, **require review from Code Owners**, block force pushes and deletion. A change
      under `deploy/` runs as root on every host (AD-21), so the other founder reviews it.
- [ ] Org Settings > Actions > General: "Allow piviki-org, and select non-piviki-org, actions"
      with: `actions/checkout@*, actions/setup-node@*, pnpm/action-setup@*, docker/setup-buildx-action@*, docker/login-action@*, docker/build-push-action@*`;
      tick "Require actions to be pinned to a full-length commit SHA".
      Workflow permissions: **Read repository contents** (the workflows ask for more per job).
- [ ] Push `piviki-core` and `piviki-infra`. The `build` workflow runs on `main`: it tests,
      builds `linux/amd64` and pushes `ghcr.io/piviki-org/piviki-core:<12-hex-commit>-<YYYYMMDD>`.
      Note the tag from the run summary: `______` (its commit goes to the bootstrap's
      `--core-commit`)
- [ ] GHCR package `piviki-core` (Org > Packages): either set visibility **public** (simplest:
      the repository is public anyway) or keep it private and fill `/etc/piviki/ghcr.env` on the
      host (secrets inventory). Under Package settings > Manage Actions access, give
      `piviki-core` **Write**.

## 2. Cloudflare: token, state bucket, OpenTofu

### 2.1 Tokens and bucket (Cloudflare dashboard)

- [ ] **R2 bucket for state and backups**: R2 > Create bucket, name `piviki-private-eu`,
      **Location: Specify jurisdiction > European Union**, public access **off**.
- [ ] **R2 API token** `r2-tofu-state-token`: R2 > Manage API tokens > Create, Object Read &
      Write, **only** bucket `piviki-private-eu` (EU jurisdiction). Store the access key id and
      secret in Bitwarden.
- [ ] **OpenTofu API token** `cloudflare-tofu-api-token`: My Profile > API Tokens > Create custom
      token with:
      - Account: Cloudflare Tunnel: Edit; Access: Apps and Policies: Edit; Access: Service Tokens:
        Edit; Access: Organizations, Identity Providers, and Groups: Edit; Account Settings: Read
      - Zone (piviki.fi only): Zone: Read; DNS: Edit
      - Client IP filtering: optional; TTL: optional
- [ ] **Tunnel read token** `CF_TUNNEL_READ_TOKEN`: custom token with only Account: Cloudflare
      Tunnel: Read, for the deploy check's connector count.
- [ ] Zero Trust: note the team name (Settings > Custom pages, `<team>.cloudflareaccess.com`).
      If Settings > Authentication already lists a One-time PIN login method, note its id.

### 2.2 Import the zone with a no-change plan

On a founder's machine with OpenTofu 1.13.2:

```sh
cd piviki-infra/tofu/prod
cp backend.hcl.example backend.hcl          # fill in the account id
cp terraform.tfvars.example terraform.tfvars # fill in ids, team name, librarian emails
export CLOUDFLARE_API_TOKEN=...             # cloudflare-tofu-api-token
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...   # r2-tofu-state-token
export TF_VAR_state_passphrase=...          # tofu-state-passphrase-prod (new, 32+ chars)
tofu init -backend-config=backend.hcl

# Import only the zone first.
tofu plan  -target=cloudflare_zone.piviki
#   expect: "1 to import, 0 to add, 0 to change, 0 to destroy"
#   If it shows any change to the zone, STOP: adjust zone.tf to match, never apply a zone change.
tofu apply -target=cloudflare_zone.piviki
tofu plan  -target=cloudflare_zone.piviki
#   expect: "No changes."  <- record this output (AC: no-change plan after import)
```

Before and after the import, record what the coming-soon page uses, so it can be compared later:

```sh
dig +short piviki.fi A; dig +short www.piviki.fi CNAME; curl -sI https://piviki.fi | head -1
```

### 2.3 Tunnel, Access and the SSH record (no public app records yet)

```sh
tofu plan    # public_records_enabled = false. Expect only additions: tunnel, its config,
             # Access apps/policies/service tokens, the OTP login method (unless its id was set),
             # random_bytes, and the ssh-prod CNAME. No change and no destroy anywhere.
tofu apply
tofu output -raw tunnel_token            # -> host cloudflared.env
tofu output tunnel_id                    # -> GitHub var CF_TUNNEL_ID
tofu output -json deploy_service_token   # -> GitHub secrets CF_ACCESS_DEPLOY_*
tofu output -json checks_service_token   # -> GitHub secrets CF_ACCESS_CHECKS_*
```

Store each output in Bitwarden (`production` collection) under its inventory name.

The service tokens expire one year after creation (`duration = "8760h"` in `access.tf`). Note
the expiry date on each Bitwarden item and put a reminder in both founders' calendars a month
before it; rotation is in `secrets-inventory.md`.

## 3. Host configuration (`/etc/piviki`)

On the host, as root (`sudo -i`), edit each file the bootstrap created empty from
`/opt/piviki/core/deploy/env-manifest` (a deploy refuses while a listed file or key is missing, or
a value is empty outside the optional `ghcr.env`).
Generate secrets on the host with `openssl rand -base64 48 | tr -d '\n/+=' | cut -c1-48` and
store each in Bitwarden first (`production` collection, inventory name), then in the file.

`/etc/piviki/core.env`
```
DATABASE_URL=postgres://piviki_core:<core-db-password>@postgres:5432/piviki
PAYLOAD_SECRET=<payload-secret>
SERVER_URL=https://admin.piviki.fi
CORS_ORIGINS=https://admin.piviki.fi
CSRF_ORIGINS=https://admin.piviki.fi
```

`/etc/piviki/postgres.env`
```
POSTGRES_PASSWORD=<postgres-superuser>
PIVIKI_CORE_DB_PASSWORD=<core-db-password>
```

`/etc/piviki/caddy.env`
```
ADMIN_HOST=admin.piviki.fi
API_HOST=api.piviki.fi
ADMIN_ORIGIN=https://admin.piviki.fi
PUBLIC_SCHEME=https
```

`/etc/piviki/cloudflared.env`
```
TUNNEL_TOKEN=<tofu output -raw tunnel_token>
```

Then `sudo /opt/piviki/infra/bootstrap/bootstrap.sh --check` (all files must be `0600 root`).

Host key for the workflow's `known_hosts`:

```sh
printf 'ssh-prod.piviki.fi %s\n' "$(cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub)"
```

## 4. GitHub Environment `production` (`piviki-core` > Settings > Environments)

- [ ] Create environment `production`. Deployment branches: `main` only. Required reviewer:
      optional (a founder).
- [ ] Variables: `ADMIN_HOST=admin.piviki.fi`, `API_HOST=api.piviki.fi`,
      `SSH_HOST=ssh-prod.piviki.fi`, `CF_ACCOUNT_ID`, `CF_TUNNEL_ID`, `DEPLOY_SSH_KNOWN_HOSTS`
      (the line from §3), `PUBLIC_RECORDS_ENABLED=false`.
- [ ] Secrets: `DEPLOY_SSH_KEY` (contents of `piviki-prod-deploy`, then delete the local file
      after storing it in Bitwarden), `CF_ACCESS_DEPLOY_CLIENT_ID`,
      `CF_ACCESS_DEPLOY_CLIENT_SECRET`, `CF_ACCESS_CHECKS_CLIENT_ID`,
      `CF_ACCESS_CHECKS_CLIENT_SECRET`, `CF_TUNNEL_READ_TOKEN`.

## 5. First deploy (records still absent)

Actions > deploy > Run workflow: environment `production`, tag from §1.

The run first checks that the tag's commit is on `main` and checks out that commit, so the deploy
checks it runs are the tag's own `deploy/checks.sh`. It then SSHes to `deploy@ssh-prod.piviki.fi` through the Tunnel with the deploy service token;
the host refuses the tag unless its checkout is clean and has the same `deploy/` (AD-21), then
pulls the tag, starts Postgres, runs migrations, starts the stack, runs the in-network
checks (first-register 404, allowlist 404s, health 200, foreign Origin 403, unknown host 404),
records the tag; the runner then checks for exactly one Tunnel connector (HTTP checks skipped
because `PUBLIC_RECORDS_ENABLED=false`) and records a GitHub deployment with the tag.

- [ ] Run is green. Record its URL: `______`

If Postgres's first start failed (for example a wrong `postgres.env`), the `pgdata` volume is
already initialised and its init script never runs again, so `piviki_core` does not exist. With
no data yet, a founder fixes the env file, then removes the stack and its volume on the host
(`sudo piviki-compose down -v`; this deletes the database) and deploys again.

## 6. Seed the first librarian over SSH

From a founder's terminal (the password never appears in argv, history or logs):

```sh
ssh ubuntu@<public-ip>
read -r EMAIL; read -rs PASSWORD      # at least 12 characters
printf '%s\n%s\n' "$EMAIL" "$PASSWORD" | sudo piviki-compose run --rm -T core seed-librarian
unset PASSWORD
```

Expected: `Created librarian id=1`. A second run refuses unless `--force` is appended. Further
librarian accounts are created by a librarian in the admin, not by this script.

## 7. Public records

```sh
cd piviki-infra/tofu/prod
# terraform.tfvars: public_records_enabled = true
tofu plan    # expect exactly 2 to add (admin and api CNAMEs), 0 to change, 0 to destroy
tofu apply
tofu plan    # expect: No changes.
```

Set the GitHub Environment variable `PUBLIC_RECORDS_ENABLED=true`, then run the deploy workflow
again with the **same tag**: now the public HTTP checks run too (through Access with the checks
token on admin). Record its URL: `______`

## 8. Production verification (story verify line, item by item)

Record each result in Implementation Notes.

1. [ ] In a fresh browser profile, open `https://admin.piviki.fi/admin`: Cloudflare Access asks
       for an email, sends a one-time PIN; after it, the Payload login appears. Sign in with the
       seeded librarian: the dashboard loads. In DevTools > Application > Cookies, `payload-token`
       is `Secure`, `HttpOnly`, `SameSite=Lax`, with domain `admin.piviki.fi` (no leading dot)
       and an expiry about 8 hours away.
2. [ ] The deploy run named `production` and a commit tag is green, and the deployment record shows
       the tag:
       `gh api "repos/piviki-org/piviki-core/deployments?environment=production&task=deploy:image&per_page=1" --jq '.[0].payload.tag'`
3. [ ] `curl -s -o /dev/null -w '%{http_code}\n' https://api.piviki.fi/api/v1/health` -> `200`;
       `/`, `/admin`, `/api/librarians`, `/api/graphql` on `api.piviki.fi` -> `404`.
4. [ ] The deploy run's checks show `first-register` 404 (in-network and public) and
       `exactly one connector`.
5. [ ] Outside scan: only `22/tcp` open (`runbook-host-setup.md` §5.1).
6. [ ] Core cannot reach the instance metadata service (`runbook-host-setup.md` §5.2).
7. [ ] `https://piviki.fi` still shows the coming-soon page, and `dig` matches the values
       recorded in §2.2.

## Later deploys

- Only the app changed (nothing under `deploy/`): run the deploy workflow with the new tag.
- `deploy/` changed (Compose, Caddy, checks, manifest, an image digest): after merge and build,
  move the checkout first (`runbook-host-setup.md` §4,
  `bootstrap.sh --move-core <commit>`), then deploy the tag. Until then the host refuses it.

## Rollback

Redeploy the previous tag (in `/var/lib/piviki/deploys.log` on the host, or the previous GitHub
deployment record). If its `deploy/` differs from the checkout's, move the checkout to its commit
first. Schema is fixed forward: a migration is never rolled back on a host.
