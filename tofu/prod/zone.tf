# Production's state holds only what every environment relies on (AD-17): this zone, the
# coming-soon records (dns.tf) and the One-time PIN login method (access.tf). Test's state
# (tofu/test) holds only test-named resources and gets the ids it needs from outputs.tf.
#
# The piviki.fi zone already exists (it serves the coming-soon page from GitHub Pages). It is
# imported, never created, and the first plan after import must report no changes. Records this
# configuration does not declare are left exactly as they are.
import {
  to = cloudflare_zone.piviki
  id = var.zone_id
}

resource "cloudflare_zone" "piviki" {
  account = {
    id = var.account_id
  }
  name = var.zone_name

  lifecycle {
    prevent_destroy = true
  }
}
