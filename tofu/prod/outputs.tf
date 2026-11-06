# Inputs for tofu/test (and any other environment's state): plain ids, so no other state ever
# reads this one or needs its passphrase.
output "zone_id" {
  description = "tofu/test variable zone_id."
  value       = cloudflare_zone.piviki.id
}

output "otp_identity_provider_id" {
  description = "tofu/test variable otp_identity_provider_id."
  value       = cloudflare_zero_trust_access_identity_provider.otp.id
}
