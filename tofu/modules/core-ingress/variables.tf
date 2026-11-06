variable "name" {
  description = "Prefix of every resource name, one per environment: piviki-test, piviki-prod."
  type        = string

  validation {
    condition     = can(regex("^piviki-[a-z]+$", var.name))
    error_message = "Use piviki-<environment>, e.g. piviki-test."
  }
}

variable "account_id" {
  description = "Cloudflare account id."
  type        = string
}

variable "zone_id" {
  description = "Id of the piviki.fi zone (owned by production's state; passed in, never referenced)."
  type        = string
}

variable "otp_identity_provider_id" {
  description = "Id of the One-time PIN login method (owned by production's state; passed in, never referenced)."
  type        = string
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

variable "hosts" {
  description = "This environment's host names: admin (librarian tool), api (/api/v1 only), ssh (deploy user)."
  type = object({
    admin = string
    api   = string
    ssh   = string
  })
}

variable "public_records_enabled" {
  description = "Create the admin and api DNS records. Keep false until the first librarian is seeded over SSH (AD-5)."
  type        = bool
  default     = false
}
