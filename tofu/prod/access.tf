# Cloudflare Access (AD-7): email one-time PIN on all of the admin host; the SSH host accepts only
# the deploy service token. A separate checks token may pass the admin app so deploy checks can
# reach Caddy; it still meets the librarian password inside.

resource "cloudflare_zero_trust_access_identity_provider" "otp" {
  count      = var.otp_identity_provider_id == null ? 1 : 0
  account_id = var.account_id
  name       = "One-time PIN"
  type       = "onetimepin"
  config     = {}
}

locals {
  otp_identity_provider_id = coalesce(
    var.otp_identity_provider_id,
    one(cloudflare_zero_trust_access_identity_provider.otp[*].id),
  )
}

resource "cloudflare_zero_trust_access_service_token" "deploy" {
  account_id = var.account_id
  name       = "piviki-prod-deploy"
  duration   = "8760h"
}

resource "cloudflare_zero_trust_access_service_token" "checks" {
  account_id = var.account_id
  name       = "piviki-prod-deploy-checks"
  duration   = "8760h"
}

# Librarians enter a one-time PIN about every 3 days per device (sign-in friction, decided
# 2026-11-04). The Payload librarian session behind it stays about 8 hours (AD-7).
resource "cloudflare_zero_trust_access_policy" "librarians" {
  account_id       = var.account_id
  name             = "piviki-prod librarians (one-time PIN)"
  decision         = "allow"
  session_duration = "72h"
  include          = [for email in var.librarian_emails : { email = { email = email } }]
  require = [
    { login_method = { id = local.otp_identity_provider_id } },
  ]
}

resource "cloudflare_zero_trust_access_policy" "checks" {
  account_id = var.account_id
  name       = "piviki-prod deploy checks (service token)"
  decision   = "non_identity"
  include = [
    { service_token = { token_id = cloudflare_zero_trust_access_service_token.checks.id } },
  ]
}

resource "cloudflare_zero_trust_access_policy" "deploy" {
  account_id = var.account_id
  name       = "piviki-prod deploy (service token)"
  decision   = "non_identity"
  include = [
    { service_token = { token_id = cloudflare_zero_trust_access_service_token.deploy.id } },
  ]
}

resource "cloudflare_zero_trust_access_application" "admin" {
  account_id                 = var.account_id
  name                       = "piviki-prod admin"
  type                       = "self_hosted"
  destinations               = [{ type = "public", uri = var.hosts.admin }]
  session_duration           = "72h"
  allowed_idps               = [local.otp_identity_provider_id]
  auto_redirect_to_identity  = true
  app_launcher_visible       = false
  http_only_cookie_attribute = true
  same_site_cookie_attribute = "lax"
  service_auth_401_redirect  = true
  policies = [
    { id = cloudflare_zero_trust_access_policy.librarians.id, precedence = 1 },
    { id = cloudflare_zero_trust_access_policy.checks.id, precedence = 2 },
  ]
}

resource "cloudflare_zero_trust_access_application" "ssh" {
  account_id                = var.account_id
  name                      = "piviki-prod ssh (deploy)"
  type                      = "self_hosted"
  destinations              = [{ type = "public", uri = var.hosts.ssh }]
  session_duration          = "1h"
  app_launcher_visible      = false
  service_auth_401_redirect = true
  policies = [
    { id = cloudflare_zero_trust_access_policy.deploy.id, precedence = 1 },
  ]
}
