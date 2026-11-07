<!-- bmad:context -->
<!-- Verified 2026-11-07 against 618743a8f51d8bcb662bd42763bc00ee3e643fb6. Managed by bmad-project-context; edits inside this block are replaced on refresh. Keep anything you want preserved outside the markers. -->

## piviki-infra

Piviki's shared infrastructure: OpenTofu with the Cloudflare provider (DNS, Tunnel, Access), the one-time host bootstrap in `bootstrap/`, and the runbooks and secrets inventory in `docs/`. What a host runs for core lives in the sibling repo `piviki-core/deploy`. Architecture decisions are cited by AD number (e.g. AD-17, AD-21).

## Policy

- Never push to `main`; open a PR, and a founder merges it.
- Name branches `<conventional-type>/<story>-<kebab-description>`, e.g. `docs/1.1-readme-tofu`.
- Write conventional commit messages whose body ends with a `Story X.Y.` line.
- Never run `tofu plan`, `apply` or `import`, or `bootstrap.sh`; they need a founder's credentials or a host. Prepare the change, and a founder runs it and shares the plan.
- Never put a value in a tracked file: account ids, emails and tokens go in the git-ignored `backend.hcl` and `terraform.tfvars`, or in Bitwarden. Give every new secret a row in `docs/secrets-inventory.md`.
- Never remove a `prevent_destroy` guard in `tofu/prod` (zone, coming-soon records, One-time PIN method).
- Put shared Cloudflare resources (the zone, records no environment owns, login methods, zone rules) only in `tofu/prod`; `tofu/test` and `modules/core-ingress` declare per-environment resources and take shared ids as variables (AD-17).
- Put every file the bootstrap installs under `bootstrap/files/<path on the host>` and list it in `bootstrap/host-files.sh`; never write one from a heredoc in a script.
- Before putting a vendor's dashboard path or default into a runbook, check it in the vendor's current docs and cite them.

## Running and verifying

- Run offline OpenTofu as `tofu -chdir=<root> init -backend=false -input=false -lockfile=readonly`, then `validate` or `test`; plain `init` stops at a bucket prompt.
- Change `.terraform.lock.hcl` only with `tofu init -upgrade` or `tofu providers lock`; CI inits with `-lockfile=readonly`.
- Don't merge a change under `bootstrap/files/etc/` until CI's `validate` job passes; it checks the files with the hosts' own programs, and a sudoers file sudo-rs rejected locked the host out on 2026-11-05.

## Conventions that differ from defaults

- Write runbook shell snippets for the founders' zsh, and give a bash form beside any zsh-only line such as `read -rs "VAR?prompt"`.

## Known pitfalls

- Match empty env values with `^[A-Z_]+=$`, never `=$`; base64 values such as `TUNNEL_TOKEN` end in `=`.
- In workflow steps, assign a command's output to a variable and check it before writing to `$GITHUB_OUTPUT`; `echo "x=$(cmd)"` doesn't fail when `cmd` fails.

<!-- /bmad:context -->
