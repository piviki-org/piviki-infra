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

variable "access_team_name" {
  description = "Zero Trust team name (the <team> in <team>.cloudflareaccess.com)."
  type        = string
}

variable "librarian_emails" {
  description = "Emails allowed through Access (one-time PIN) to the admin host."
  type        = list(string)

  validation {
    condition     = length(var.librarian_emails) > 0
    error_message = "At least one librarian email is required."
  }
}

variable "otp_identity_provider_id" {
  description = "Id of an existing One-time PIN login method, if the account already has one. Leave null to create it."
  type        = string
  default     = null
}

variable "public_records_enabled" {
  description = "Create the admin and api DNS records. Keep false until the first librarian is seeded over SSH (AD-5)."
  type        = bool
  default     = false
}

variable "hosts" {
  description = "Host names of this environment. Production's are the defaults."
  type = object({
    admin = string
    api   = string
    ssh   = string
  })
  default = {
    admin = "admin.piviki.fi"
    api   = "api.piviki.fi"
    ssh   = "ssh-prod.piviki.fi"
  }
}
