# Secrets inventory

Every secret Piviki uses, by name only. Nothing here is a value. No secret is ever put in EC2
user data, an image, a repository or a log.

**Source of truth: Bitwarden** (AD-17), the free two-person organisation `Piviki` in the EU
region (bitwarden.eu), both founders Owners, each with their own login and two-step login (setup:
`runbook-host-setup.md` §0). One item per row, named as in the first column, in the collection of
its environment (`production` or `test`); values stored as text. A value goes into Bitwarden
first, then to the one place listed for it. The only secret not in Bitwarden is the `age` backup
private key, which stays offline.

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
`PUBLIC_SCHEME`; `/etc/piviki/environment` (`production` or `test`).

## GitHub Environment secrets (`piviki-org/piviki-core`, per environment)

| Name | Holds | Source |
|---|---|---|
| `DEPLOY_SSH_KEY` | Private ed25519 key of the host's `deploy` user | Generated on a founder's machine; public half passed to `bootstrap.sh --deploy-key`. |
| `CF_ACCESS_DEPLOY_CLIENT_ID`, `CF_ACCESS_DEPLOY_CLIENT_SECRET` | Access service token for `ssh-<env>` | `tofu output -json deploy_service_token` |
| `CF_ACCESS_CHECKS_CLIENT_ID`, `CF_ACCESS_CHECKS_CLIENT_SECRET` | Access service token allowed on the admin app, for deploy checks | `tofu output -json checks_service_token` |
| `CF_TUNNEL_READ_TOKEN` | Cloudflare API token, account permission "Cloudflare Tunnel: Read" only | Created by hand in the Cloudflare dashboard |

`GITHUB_TOKEN` is the workflow's own token; nothing else is stored in repository-level secrets.

## Founder machine (OpenTofu, `piviki-infra/tofu/<env>`)

| Name | Held as | Notes |
|---|---|---|
| `cloudflare-tofu-api-token` | `CLOUDFLARE_API_TOKEN` | Scopes in `runbook-first-deploy.md` §2. |
| `r2-tofu-state-token` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | R2 API token, Object Read & Write, scoped to the private EU bucket only. |
| `tofu-state-passphrase-<env>` | `TF_VAR_state_passphrase` | Encrypts state and plans; losing it loses the state. |

## Provider consoles

AWS, Cloudflare, GitHub and Bitwarden are reached with each founder's own login and MFA. There are no shared console logins and no AWS access keys (no IAM user or role is created).

## Rotation and revocation

- Access service tokens (`deploy_service_token`, `checks_service_token`) expire one year after
  creation. A month before (calendar reminder), a founder runs
  `tofu apply -replace=cloudflare_zero_trust_access_service_token.<name>`, stores the new id and
  secret in Bitwarden, then updates the GitHub Environment secrets.

- On the move to OVH (AD-17 step 4): new tunnel token, deploy key, service tokens and GHCR
  credentials for OVH; the AWS ones are revoked.
- A leaked value: rotate at its source, update Bitwarden, then the place its row lists; redeploy or restart the
  one service that reads it (`sudo piviki-compose up -d --force-recreate <service>`).
