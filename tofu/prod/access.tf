# The Access One-time PIN login method (AD-7). Shared: every environment's Access apps require
# it, so it lives only in production's state (AD-17). Test's state takes its id as a plain input
# (otp_identity_provider_id output), never a reference.
#
# An account has at most one One-time PIN method. If it already has one, set
# otp_identity_provider_import_id and the first apply imports it instead of creating another.

import {
  for_each = var.otp_identity_provider_import_id == null ? toset([]) : toset([var.otp_identity_provider_import_id])
  to       = cloudflare_zero_trust_access_identity_provider.otp
  id       = "accounts/${var.account_id}/${each.value}"
}

resource "cloudflare_zero_trust_access_identity_provider" "otp" {
  account_id = var.account_id
  name       = "One-time PIN"
  type       = "onetimepin"
  config     = {}

  lifecycle {
    prevent_destroy = true
  }
}

# Production's own Tunnel, Access apps and records come with the production start
# (epic-soft-open), as a call to the same module test uses:
#   module "core_ingress" { source = "../modules/core-ingress" ... }
