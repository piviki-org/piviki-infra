# The coming-soon page's records (apex and www, GitHub Pages). Shared: piviki.fi must keep serving
# the coming-soon page until the soft open (AD-17), so they live only in production's state. They
# are imported, never created, and the plan after import must report no changes: each entry in
# coming_soon_records must hold the live record's exact values (docs/runbook-first-deploy.md).
# The soft open replaces them in one apply (epic-soft-open). Records not listed here are not
# managed by this state.

import {
  for_each = var.coming_soon_records
  to       = cloudflare_dns_record.coming_soon[each.key]
  id       = "${var.zone_id}/${each.value.id}"
}

resource "cloudflare_dns_record" "coming_soon" {
  for_each = var.coming_soon_records

  zone_id = cloudflare_zone.piviki.id
  name    = each.value.name
  type    = each.value.type
  content = each.value.content
  proxied = each.value.proxied
  ttl     = each.value.ttl
  comment = each.value.comment

  lifecycle {
    prevent_destroy = true
  }
}
