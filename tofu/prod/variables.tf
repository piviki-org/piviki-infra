variable "state_passphrase" {
  description = "Passphrase for OpenTofu state and plan encryption (TF_VAR_state_passphrase)."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.state_passphrase) >= 32
    error_message = "Use a passphrase of at least 32 characters."
  }
}

variable "account_id" {
  description = "Cloudflare account id."
  type        = string
}

variable "zone_id" {
  description = "Id of the existing piviki.fi zone, imported (never created) by this configuration."
  type        = string
}

variable "zone_name" {
  description = "The zone's name."
  type        = string
  default     = "piviki.fi"
}

variable "otp_identity_provider_import_id" {
  description = "Id of the account's existing One-time PIN login method, to import it. Leave null to create one."
  type        = string
  default     = null
}

variable "coming_soon_records" {
  description = "The live coming-soon records to import, keyed by a stable name (apex-a-1, www, ...). Values must equal the live record's."
  type = map(object({
    id      = string
    name    = string
    type    = string
    content = string
    proxied = bool
    ttl     = number
    comment = optional(string)
  }))

  validation {
    condition     = length(var.coming_soon_records) > 0
    error_message = "List the coming-soon records (apex and www) so the page stays under production's state."
  }
}
