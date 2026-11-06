# Secrets inventory

Every secret Piviki uses, by name only. Nothing here is a value. No secret is ever put in EC2
user data, an image, a repository or a log.

**Source of truth: Bitwarden** (AD-17), the free two-person organisation `Piviki` in the EU
region (bitwarden.eu), both founders Owners, each with their own login and two-step login (setup:
`runbook-host-setup.md` §0). One item per row, named as in the first column, in the collection of
its environment (`production` or `test`); values stored as text. A value goes into Bitwarden
first, then to the one place listed for it. The only secret not in Bitwarden is the `age` backup
private key, which stays offline.

Each environment has its own value for every per-environment row (`<env>` is `prod` or `test`).
No production value is ever copied to the `test` collection, the test host or the GitHub
Environment `test` (AD-17). The founder-only OpenTofu credentials that can change shared or
production resources are kept in `production` and never leave a founder's machine.

Each host service reads only its own root-owned file under `/etc/piviki/` (directory `0700 root`,
files `0600 root`). The files and keys are exactly those in
[`piviki-core/deploy/env-manifest`](https://github.com/piviki-org/piviki-core/blob/main/deploy/env-manifest)
(AD-21): `bootstrap.sh` creates them empty from it, and a deploy refuses while one is missing.
A change to that list is a change to this table.

## Host: `/etc/piviki/` (one file per service)

| Name | File and key | Read by | Notes |
|---|---|---|---|
| `piviki-<env>-payload-secret` | `core.env` `PAYLOAD_SECRET` | core | 48+ random chars (`openssl rand -base64 48`). Rotating it signs every librarian out. |
| `piviki-<env>-core-db-password` | `core.env` inside `DATABASE_URL`, and `postgres.env` `PIVIKI_CORE_DB_PASSWORD` | core, postgres (first init only) | The non-superuser role `piviki_core`. The one value held in two files: postgres needs it once to create the role. |
| `piviki-<env>-postgres-superuser` | `postgres.env` `POSTGRES_PASSWORD` | postgres | Superuser `postgres`; nothing connects with it in normal operation. |
| `piviki-<env>-tunnel-token` | `cloudflared.env` `TUNNEL_TOKEN` | cloudflared | `tofu output -raw tunnel_token`. |
| `piviki-<env>-ghcr-pull` | `ghcr.env` `GHCR_USER`, `GHCR_TOKEN` | `piviki-core` `deploy/deploy.sh` (`docker login`) | Only if the GHCR package is private: a classic PAT with `read:packages` only. Leave empty if the package is public. |

Non-secret runtime configuration in the same files (environment-specific, AD-17): `core.env`
`SERVER_URL`, `CORS_ORIGINS`, `CSRF_ORIGINS`; `caddy.env` `ADMIN_HOST`, `API_HOST`, `ADMIN_ORIGIN`,
`PUBLIC_SCHEME`. The environment name has one source, `/etc/piviki/environment` (`production` or
`test`, written by the bootstrap); `deploy.sh` passes it to core, and no env file repeats it. Host
names must agree with it: on test every host's first label is `test` or starts `test-`, on
production none is (core refuses to start otherwise; the deploy checks fail).

On the test host (Bitwarden `test`): `SERVER_URL`, `CORS_ORIGINS`, `CSRF_ORIGINS` =
`https://test-admin.piviki.fi`; `ADMIN_HOST=test-admin.piviki.fi`, `API_HOST=test-api.piviki.fi`,
`ADMIN_ORIGIN=https://test-admin.piviki.fi`.

## GitHub Environment secrets (`piviki-org/piviki-core`, per environment: `test` now, `production` from the production start)

| Name | Holds | Source |
|---|---|---|
| `DEPLOY_SSH_KEY` | Private ed25519 key of the host's `deploy` user (`piviki-<env>-deploy`) | Generated on a founder's machine; public half passed to `bootstrap.sh --deploy-key`. |
| `CF_ACCESS_DEPLOY_CLIENT_ID`, `CF_ACCESS_DEPLOY_CLIENT_SECRET` | Access service token `piviki-<env>-deploy` for `ssh-<env>` | `tofu -chdir=tofu/<env> output -json deploy_service_token` |
| `CF_TUNNEL_READ_TOKEN` | Cloudflare API token `piviki-<env>-tunnel-read-token`, account permission "Cloudflare Tunnel: Read" only; one per environment | Created by hand in the Cloudflare dashboard |

Variables (not secret) of the GitHub Environment `test`: `ADMIN_HOST=test-admin.piviki.fi`,
`API_HOST=test-api.piviki.fi`, `SSH_HOST=ssh-test.piviki.fi`, `CF_ACCOUNT_ID`, `CF_TUNNEL_ID`,
`DEPLOY_SSH_KNOWN_HOSTS`, `PUBLIC_RECORDS_ENABLED` (`runbook-first-deploy.md` §4).

`GITHUB_TOKEN` is the workflow's own token; nothing else is stored in repository-level secrets.

## Founder machine (OpenTofu, `piviki-infra/tofu/prod` and `tofu/test`)

| Name | Collection | Held as | Notes |
|---|---|---|---|
| `cloudflare-tofu-api-token` | `production` | `CLOUDFLARE_API_TOKEN` | Scopes in `runbook-first-deploy.md` §2.1. Used for both states; never on a host or in GitHub. |
| `r2-tofu-state-token-prod` | `production` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | R2 API token, Object Read & Write, scoped to `piviki-prod-private-eu` only. For `tofu/prod`; never on a host or in GitHub. |
| `r2-tofu-state-token-test` | `test` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | R2 API token, Object Read & Write, scoped to `piviki-test-private-eu` only. For `tofu/test`; cannot reach production's bucket. |
| `tofu-state-passphrase-prod` | `production` | `TF_VAR_state_passphrase` | Encrypts production's (shared) state and plans; losing it loses the state. |
| `tofu-state-passphrase-test` | `test` | `TF_VAR_state_passphrase` | Test's own; encrypts only `tofu/test`'s state. Never production's. |

## Provider consoles

AWS, Cloudflare, GitHub and Bitwarden are reached with each founder's own login and MFA. There are no shared console logins and no AWS access keys (no IAM user or role is created).

## Rotation and revocation

- The Access deploy service token (`deploy_service_token`) expires one year after creation. A
  month before (calendar reminder), a founder runs, for that environment,
  `tofu -chdir=tofu/<env> apply -replace=module.core_ingress.cloudflare_zero_trust_access_service_token.deploy`,
  stores the new id and secret in Bitwarden, then updates the GitHub Environment secrets. No token passes Access on
  `admin`: only librarians with a one-time PIN do (decided 2026-11-04).

- At the production start (`epic-soft-open`): production's tunnel token, deploy key, deploy
  service token, tunnel read token, host secrets and GHCR credentials are created new in
  Bitwarden `production`; nothing moves from test.
- A leaked value: rotate at its source, update Bitwarden, then the place its row lists; redeploy or restart the
  one service that reads it (`sudo piviki-compose up -d --force-recreate <service>`).
