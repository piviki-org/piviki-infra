# Only the records declared here are managed. The apex and www records of the coming-soon page
# are not, and no change here touches them.

locals {
  tunnel_target = "${cloudflare_zero_trust_tunnel_cloudflared.env.id}.cfargotunnel.com"
}

# The deploy path; Access-protected, service token only. Needed before seeding.
resource "cloudflare_dns_record" "ssh" {
  zone_id = cloudflare_zone.piviki.id
  name    = var.hosts.ssh
  type    = "CNAME"
  content = local.tunnel_target
  proxied = true
  ttl     = 1
  comment = "piviki-infra: Tunnel SSH for the deploy user"
}

# Added only after the first librarian is seeded over SSH (AD-5): public_records_enabled = true.
resource "cloudflare_dns_record" "admin" {
  count   = var.public_records_enabled ? 1 : 0
  zone_id = cloudflare_zone.piviki.id
  name    = var.hosts.admin
  type    = "CNAME"
  content = local.tunnel_target
  proxied = true
  ttl     = 1
  comment = "piviki-infra: librarian tool, behind Access"
}

resource "cloudflare_dns_record" "api" {
  count   = var.public_records_enabled ? 1 : 0
  zone_id = cloudflare_zone.piviki.id
  name    = var.hosts.api
  type    = "CNAME"
  content = local.tunnel_target
  proxied = true
  ttl     = 1
  comment = "piviki-infra: /api/v1 only"
}
