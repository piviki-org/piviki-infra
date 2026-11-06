# The test environment's Cloudflare resources (AD-17): only test-named ones. Destroying this state
# (tofu -chdir=tofu/test plan -destroy) removes test's Tunnel, Access apps, policies, deploy token
# and records, and nothing production or the coming-soon page uses.
module "core_ingress" {
  source = "../modules/core-ingress"

  name                     = "piviki-test"
  account_id               = var.account_id
  zone_id                  = var.zone_id
  otp_identity_provider_id = var.otp_identity_provider_id
  access_team_name         = var.access_team_name
  librarian_emails         = var.librarian_emails
  hosts                    = var.hosts
  public_records_enabled   = var.public_records_enabled
}
