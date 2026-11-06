# core-ingress: one environment's route in to core's host (AD-17): its Tunnel and the Tunnel's
# ingress, the Access apps and policies on its admin and deploy SSH hosts with the deploy service
# token, and the ssh, admin and api DNS records. The patron site's Worker is not here.
#
# Called by tofu/test (and, from epic-soft-open, by tofu/prod), so every environment gets the same
# resources by construction. It references no shared resource itself: the zone id and the
# One-time PIN login method id come in as plain inputs, so the calling state never owns them.
terraform {
  required_version = "~> 1.13.2"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.28"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}
