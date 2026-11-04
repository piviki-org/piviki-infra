# The piviki.fi zone already exists (it serves the coming-soon page from GitHub Pages). It is
# imported, never created, and the first plan after import must report no changes. Records this
# configuration does not declare, such as the apex and www records of the coming-soon page, are
# left exactly as they are: OpenTofu manages only the records in dns.tf.
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
