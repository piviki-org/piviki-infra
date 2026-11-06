# Runbook: first deploy to the test environment (story 1.1)

The order matters (AD-5): the first librarian is seeded over SSH **before** the `test-admin` and
`test-api` DNS records exist. A founder performs every console step; the agent guides. Record each
step's date, who ran it and any output asked for in the story's Implementation Notes.

Two OpenTofu states, one per environment (AD-17): `tofu/prod` holds **only** the shared resources
(the `piviki.fi` zone, its coming-soon records, the Access One-time PIN login method) and is
created first; `tofu/test` holds only test-named resources (Tunnel, Access, records, through the
`modules/core-ingress` module), takes the two shared ids as plain values and never reads
production's state or its passphrase. Production's own Tunnel, Access and host come with the
production start (`epic-soft-open`).

Bitwarden: values for test go in the `test` collection; shared founder credentials that can
change production's resources (production's OpenTofu API token, R2 state token and state
passphrase) stay in `production`. Nothing from `production` is copied to the test host or
test's GitHub Environment.

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

## 2. Cloudflare: tokens, state bucket, OpenTofu

### 2.1 Tokens and bucket (Cloudflare dashboard)

- [ ] **Two OpenTofu state buckets, one per environment** (AD-17): R2 > Create bucket, each with
      **Location: Specify jurisdiction > European Union** (cannot be changed later), public
      access **off**, and **no lifecycle or lock rule**. Each holds only that environment's state:
      - `piviki-prod-tofu-state-eu`
      - `piviki-test-tofu-state-eu`
      Backups and erasure records go to separate data buckets (`piviki-<env>-private-eu`),
      created by the stories that first write to them, never these.
- [ ] **One R2 API token per state bucket**: R2 > Manage API tokens > Create (table below). The
      confirmation page shows a token value, an **Access Key ID** and a **Secret Access Key**; the
      secret is shown only once. Store only the **Access Key ID** and **Secret Access Key** in the
      token's Bitwarden item: OpenTofu's S3 backend reads them as `AWS_ACCESS_KEY_ID` and
      `AWS_SECRET_ACCESS_KEY`. Do not store the token value: OpenTofu does not use it, and the
      secret is derived from it, so keeping it is one more copy of the same secret. Lost secret:
      roll or recreate the token.
- [ ] **One OpenTofu API token per environment**: My Profile > API Tokens > Create custom token
      (table below). Client IP filtering and TTL are optional.
- [ ] **Tunnel read token for test**: My Profile > API Tokens > Create custom token (table below).
- [ ] **Zero Trust** (runs Access and Tunnels; Cloudflare dashboard > Zero Trust):
      - First visit only: choose a **team name** and the **Free** plan (up to 50 users). The team
        name gives the login domain `<team>.cloudflareaccess.com`, where librarians enter their
        email and PIN; it goes in `tofu/test/terraform.tfvars` as `access_team_name`, and the
        deploy check expects `test-admin` to redirect to it.
      - Already set up: note the team name (Zero Trust > Settings > Team name and domain). If it
        is ever renamed, update `access_team_name` and re-apply `tofu/test`.
      - Zero Trust > Integrations > Identity providers: if **One-time PIN** is listed, note its id
        (in the URL when you open it) for `otp_identity_provider_import_id` in
        `tofu/prod/terraform.tfvars`, so §2.2 imports it instead of creating a second one. If it
        is not listed, leave that unset and §2.2 creates it. New organisations get Cloudflare's
        own identity provider by default, not One-time PIN; leave it as it is: Piviki's Access
        apps allow only One-time PIN (`allowed_idps`).

Every token here is founder use only, kept in Bitwarden under its name; only the Tunnel read token
is copied anywhere else (GitHub Environment `test`). Production's tokens are never used for test
work.

| Token | Bitwarden | Permissions | Used by |
|---|---|---|---|
| `r2-tofu-state-token-prod` | `production` (Access Key ID, Secret Access Key) | R2: Object Read & Write, **only** bucket `piviki-prod-tofu-state-eu` | `tofu/prod` state (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) |
| `r2-tofu-state-token-test` | `test` (Access Key ID, Secret Access Key) | R2: Object Read & Write, **only** bucket `piviki-test-tofu-state-eu` | `tofu/test` state (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`); cannot reach production's bucket |
| `cloudflare-tofu-api-token-prod` | `production` | see the permission table | `tofu/prod` (`CLOUDFLARE_API_TOKEN`) |
| `cloudflare-tofu-api-token-test` | `test` | see the permission table | `tofu/test` (`CLOUDFLARE_API_TOKEN`) |
| `piviki-test-tunnel-read-token` | `test` | Account: Cloudflare Tunnel: **Read** only | Deploy check's connector count (GitHub `CF_TUNNEL_READ_TOKEN`); production gets its own at the production start |

OpenTofu API token permissions (custom token; set exactly these, nothing else):

| Permission | `-prod` | `-test` | Why |
|---|---|---|---|
| Account: Access: Organizations, Identity Providers, and Groups | Edit | Read | Prod owns the shared One-time PIN login method; test only uses its id |
| Account: Account Settings | Read | Read | The provider looks up the account |
| Zone (`piviki.fi` only): Zone | Read | Read | Prod imports the zone; test finds it |
| Zone (`piviki.fi` only): DNS | Edit | Edit | Prod imports the coming-soon records; test adds `ssh-test`, `test-admin`, `test-api` |
| Account: Cloudflare Tunnel | — | Edit | Test's Tunnel and its routes |
| Account: Access: Apps and Policies | — | Edit | Access on `test-admin` and `ssh-test` |
| Account: Access: Service Tokens | — | Edit | Test's deploy service token |

Neither gets any R2, API Tokens or Account Settings edit permission. The production start adds
Tunnel and Access app permissions to `-prod` when it adds production's `core_ingress`.

Accepted risk (AD-17): Cloudflare cannot limit Tunnel or Access permissions to test's resources,
and DNS edit covers the whole zone, so test's token can still change production's routing. Keep it
in Bitwarden `test` only and rotate it if it leaks. The environments have separate tokens because
that is best practice, even though it holds little value here: there is only one Cloudflare
account, so both tokens reach the same account and the same `piviki.fi` zone.

### 2.2 Production's shared state: zone, coming-soon records, login method (no change)

Before anything, record what the coming-soon page uses, so it can be compared later:

```sh
dig +short piviki.fi A; dig +short piviki.fi AAAA; dig +short www.piviki.fi CNAME
curl -sI https://piviki.fi | head -1
```

In the Cloudflare dashboard (DNS > Records for `piviki.fi`), note every record that serves the
coming-soon page (the apex and `www`): its id (the record's Edit panel, or the API's
`GET zones/<zone id>/dns_records`), name, type, content, proxy status, TTL and comment. Copy them
into `coming_soon_records` in `terraform.tfvars`, one entry each, values exactly as live.

On a founder's machine with OpenTofu 1.13.2:

```sh
cd piviki-infra/tofu/prod
cp backend.hcl.example backend.hcl          # fill in the account id
cp terraform.tfvars.example terraform.tfvars # account id, zone id, coming_soon_records, and
                                            # otp_identity_provider_import_id if one exists
export CLOUDFLARE_API_TOKEN=...             # cloudflare-tofu-api-token-prod
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...   # r2-tofu-state-token-prod
export TF_VAR_state_passphrase=...          # tofu-state-passphrase-prod (new, 32+ chars, Bitwarden production)
tofu init -backend-config=backend.hcl

tofu plan
#   expect: the zone and every coming_soon_records entry "to import", 0 to change, 0 to destroy;
#   the One-time PIN login method "to import" if its id was set, else "1 to add".
#   If the plan shows ANY change to the zone or a coming-soon record, STOP: correct
#   terraform.tfvars (or zone.tf) to the live value and plan again. Never apply such a change.
tofu apply
tofu plan
#   expect: "No changes."  <- record this output (AC: no-change plan after import)
tofu output                                 # zone_id, otp_identity_provider_id: inputs for test
```

Then confirm `https://piviki.fi` still shows the coming-soon page and `dig` matches the values
recorded above.

### 2.3 Test's state: Tunnel, Access and the SSH record (no public app records yet)

```sh
cd piviki-infra/tofu/test
cp backend.hcl.example backend.hcl          # account id; bucket piviki-test-tofu-state-eu
cp terraform.tfvars.example terraform.tfvars # account id, team name, librarian emails, and the
                                            # zone_id / otp_identity_provider_id from §2.2's output
export CLOUDFLARE_API_TOKEN=...             # cloudflare-tofu-api-token-test (never prod's)
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...   # r2-tofu-state-token-test (never prod's)
export TF_VAR_state_passphrase=...          # tofu-state-passphrase-test (new, 32+ chars, Bitwarden test;
                                            # never production's)
tofu init -backend-config=backend.hcl
tofu plan    # public_records_enabled = false. Expect only additions, all named piviki-test or on
             # test hosts: the Tunnel and its config, random_bytes, the deploy service token, two
             # Access policies, two Access apps, and the ssh-test CNAME. Nothing imported, changed
             # or destroyed.
tofu apply
tofu output -raw tunnel_token            # -> host cloudflared.env
tofu output tunnel_id                    # -> GitHub var CF_TUNNEL_ID
tofu output -json deploy_service_token   # -> GitHub secrets CF_ACCESS_DEPLOY_*
tofu plan -destroy                       # AC: lists only test's resources above: no zone, no
                                         # coming-soon record, no login method. Do NOT apply it.
```

Store each output in Bitwarden (`test` collection) under its inventory name. Record the
`plan -destroy` resource list in the story notes.

The deploy service token expires one year after creation (`duration = "8760h"` in
`modules/core-ingress/access.tf`). Note the expiry date on its Bitwarden item and put a reminder in
both founders' calendars a month before it; rotation is in `secrets-inventory.md`.

## 3. Host configuration (`/etc/piviki` on the test host)

On the host, as root (`sudo -i`), edit each file the bootstrap created empty from
`/opt/piviki/core/deploy/env-manifest` (a deploy refuses while a listed file or key is missing, or
a value is empty outside the optional `ghcr.env`).
Generate secrets on the host with `openssl rand -base64 48 | tr -d '\n/+=' | cut -c1-48` and
store each in Bitwarden first (`test` collection, inventory name), then in the file. Every value
is test's own: none is copied from production.

The environment name is **not** in these files: it is `/etc/piviki/environment` (`test`, written
by the bootstrap), which `deploy.sh` passes to core. Core refuses to start, and the deploy checks
fail, if a host name below disagrees with it (on test, every host's first label is `test` or
starts `test-`).

`/etc/piviki/core.env`
```
DATABASE_URL=postgres://piviki_core:<core-db-password>@postgres:5432/piviki
PAYLOAD_SECRET=<payload-secret>
SERVER_URL=https://test-admin.piviki.fi
CORS_ORIGINS=https://test-admin.piviki.fi
CSRF_ORIGINS=https://test-admin.piviki.fi
```

`/etc/piviki/postgres.env`
```
POSTGRES_PASSWORD=<postgres-superuser>
PIVIKI_CORE_DB_PASSWORD=<core-db-password>
```

`/etc/piviki/caddy.env`
```
ADMIN_HOST=test-admin.piviki.fi
API_HOST=test-api.piviki.fi
ADMIN_ORIGIN=https://test-admin.piviki.fi
PUBLIC_SCHEME=https
```

`/etc/piviki/cloudflared.env`
```
TUNNEL_TOKEN=<tofu -chdir=tofu/test output -raw tunnel_token>
```

Then `sudo /opt/piviki/infra/bootstrap/bootstrap.sh --check` (all files must be `0600 root`).

Host key for the workflow's `known_hosts`:

```sh
printf 'ssh-test.piviki.fi %s\n' "$(cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub)"
```

## 4. GitHub Environment `test` (`piviki-core` > Settings > Environments)

- [ ] Create environment `test`. Deployment branches: `main` only. Required reviewer: optional.
- [ ] Variables: `ADMIN_HOST=test-admin.piviki.fi`, `API_HOST=test-api.piviki.fi`,
      `SSH_HOST=ssh-test.piviki.fi`, `CF_ACCOUNT_ID`, `CF_TUNNEL_ID` (test's), `DEPLOY_SSH_KNOWN_HOSTS`
      (the line from §3), `PUBLIC_RECORDS_ENABLED=false`. The deploy checks fail if `ADMIN_HOST`
      or `API_HOST` is not a test host name.
- [ ] Secrets: `DEPLOY_SSH_KEY` (contents of `piviki-test-deploy`, then delete the local file
      after storing it in Bitwarden `test`), `CF_ACCESS_DEPLOY_CLIENT_ID`,
      `CF_ACCESS_DEPLOY_CLIENT_SECRET` (test's), `CF_TUNNEL_READ_TOKEN`
      (`piviki-test-tunnel-read-token`). No production value goes here.

## 5. Move the checkout, then the first deploy (records still absent)

This story changed `piviki-core/deploy/` (the environment name passed to core, the host-name
checks), so the host's checkout must move to the new commit before its tag deploys (AD-21).
After the core PR is merged and `build` on `main` is green, note the new tag
`<commit>-<date>`: `______`. On the host:

```sh
sudo git -C /opt/piviki/infra pull --ff-only     # only if piviki-infra's bootstrap changed
sudo /opt/piviki/infra/bootstrap/bootstrap.sh --move-core <commit>
sudo /opt/piviki/infra/bootstrap/bootstrap.sh --check
```

Then Actions > deploy > Run workflow: environment `test`, that tag.

The run first checks that the tag's commit is on `main` and checks out that commit, so the deploy
checks it runs are the tag's own `deploy/checks.sh`. It then SSHes to `deploy@ssh-test.piviki.fi`
through the Tunnel with the deploy service token; the host refuses the tag unless its checkout is
clean and has the same `deploy/` (AD-21), then pulls the tag, starts Postgres, runs migrations
(they fail, and the tag is not recorded, if a host name in `core.env` is not a test name), starts
the stack, runs the
in-network checks (host names agree with `test`, first-register 404, allowlist 404s, health 200,
foreign Origin 403, unknown host 404), records the tag; the runner then checks the host names
and exactly one Tunnel connector (HTTP checks skipped because `PUBLIC_RECORDS_ENABLED=false`) and
records a GitHub deployment with the tag for `test`.

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
cd piviki-infra/tofu/test
# terraform.tfvars: public_records_enabled = true
tofu plan    # expect exactly 2 to add (test-admin and test-api CNAMEs), 0 to change, 0 to destroy
tofu apply
tofu plan    # expect: No changes.
```

Set the GitHub Environment `test` variable `PUBLIC_RECORDS_ENABLED=true`, then run the deploy
workflow again with the **same tag**: now the public HTTP checks run too. On `test-admin` they only
confirm that an unauthenticated request is redirected to `<team>.cloudflareaccess.com` (nothing
passes Access without a PIN); the admin-side checks ran in-network on the host. Record its URL:
`______`

- [ ] The run's checks show `admin is behind Access (302 to https://<team>.cloudflareaccess.com/…)`.
      If Access answers a non-browser request differently (another status, no redirect), record
      what it returned and adjust `expect_access_redirect` in `piviki-core/deploy/checks.sh`.

## 8. Test verification (story verify line, item by item)

Record each result in Implementation Notes.

1. [ ] In a fresh browser profile, open `https://test-admin.piviki.fi/admin`: Cloudflare Access
       asks for an email, sends a one-time PIN; after it, the Payload login appears. Sign in with
       the seeded librarian: the dashboard loads. In DevTools > Application > Cookies,
       `payload-token` is `Secure`, `HttpOnly`, `SameSite=Lax`, with domain `test-admin.piviki.fi`
       (no leading dot) and an expiry about 8 hours away.
2. [ ] The deploy run named `test` and a commit tag is green, and the deployment record shows
       the tag:
       `gh api "repos/piviki-org/piviki-core/deployments?environment=test&task=deploy:image&per_page=1" --jq '.[0].payload.tag'`
3. [ ] `curl -s -o /dev/null -w '%{http_code}\n' https://test-api.piviki.fi/api/v1/health` -> `200`;
       `/`, `/admin`, `/api/librarians`, `/api/graphql` on `test-api.piviki.fi` -> `404`.
4. [ ] The deploy run's checks show `first-register` 404 (in-network, in the `deploy` step),
       `admin is behind Access` and `exactly one connector`.
5. [ ] Outside scan: only `22/tcp` open (`runbook-host-setup.md` §5.1).
6. [ ] Core cannot reach the instance metadata service (`runbook-host-setup.md` §5.2).
7. [ ] `tofu -chdir=tofu/test plan -destroy` (§2.3) names no zone, coming-soon record or login
       method; `tofu -chdir=tofu/prod plan` still says `No changes.`
8. [ ] `https://piviki.fi` still shows the coming-soon page, and `dig` matches the values
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
