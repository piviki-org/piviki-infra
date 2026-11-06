# Cloudflare Access (AD-7): email one-time PIN on all of the admin host; the SSH host accepts only
# the deploy service token. Deploy checks never pass Access on admin: the public check only
# confirms admin redirects to the Access login, and the admin-side checks run in-network on the
# host (decided 2026-11-04). The only planned exception is the one-time import script's own
# service token (AD-7, epic-initial-load), revoked after the initial load. The One-time PIN
# login method itself is shared and lives in production's state; only its id comes in.

resource "cloudflare_zero_trust_access_service_token" "deploy" {
  account_id = var.account_id
  name       = "${var.name}-deploy"
  duration   = "8760h"
}

# Librarians enter a one-time PIN about every 3 days per device (sign-in friction, decided
# 2026-11-04). The Payload librarian session behind it stays about 8 hours (AD-7).
resource "cloudflare_zero_trust_access_policy" "librarians" {
  account_id       = var.account_id
  name             = "${var.name} librarians (one-time PIN)"
  decision         = "allow"
  session_duration = "72h"
  include          = [for email in var.librarian_emails : { email = { email = email } }]
  require = [
    { login_method = { id = var.otp_identity_provider_id } },
  ]
}

resource "cloudflare_zero_trust_access_policy" "deploy" {
  account_id = var.account_id
  name       = "${var.name} deploy (service token)"
  decision   = "non_identity"
  include = [
    { service_token = { token_id = cloudflare_zero_trust_access_service_token.deploy.id } },
  ]
}

resource "cloudflare_zero_trust_access_application" "admin" {
  account_id                 = var.account_id
  name                       = "${var.name} admin"
  type                       = "self_hosted"
  destinations               = [{ type = "public", uri = var.hosts.admin }]
  session_duration           = "72h"
  allowed_idps               = [var.otp_identity_provider_id]
  auto_redirect_to_identity  = true
  app_launcher_visible       = false
  http_only_cookie_attribute = true
  same_site_cookie_attribute = "lax"
  service_auth_401_redirect  = true
  policies = [
    { id = cloudflare_zero_trust_access_policy.librarians.id, precedence = 1 },
  ]
}

resource "cloudflare_zero_trust_access_application" "ssh" {
  account_id                = var.account_id
  name                      = "${var.name} ssh (deploy)"
  type                      = "self_hosted"
  destinations              = [{ type = "public", uri = var.hosts.ssh }]
  session_duration          = "1h"
  app_launcher_visible      = false
  service_auth_401_redirect = true
  policies = [
    { id = cloudflare_zero_trust_access_policy.deploy.id, precedence = 1 },
  ]
}
