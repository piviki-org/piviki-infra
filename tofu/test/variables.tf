variable "state_passphrase" {
  description = "Test's own passphrase for OpenTofu state and plan encryption (TF_VAR_state_passphrase)."
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

# The two shared ids, copied from production's outputs (tofu -chdir=tofu/prod output). Plain
# values: this state never references a shared resource, so destroying it removes none.
variable "zone_id" {
  description = "Id of the piviki.fi zone: tofu/prod output zone_id."
  type        = string
}

variable "otp_identity_provider_id" {
  description = "Id of the One-time PIN login method: tofu/prod output otp_identity_provider_id."
  type        = string
}

variable "access_team_name" {
  description = "Zero Trust team name (the <team> in <team>.cloudflareaccess.com)."
  type        = string
}

variable "librarian_emails" {
  description = "Emails allowed through Access (one-time PIN) to test-admin."
  type        = list(string)
}

variable "public_records_enabled" {
  description = "Create the test-admin and test-api DNS records. Keep false until the first librarian is seeded over SSH (AD-5)."
  type        = bool
  default     = false
}

variable "hosts" {
  description = "Test's host names."
  type = object({
    admin = string
    api   = string
    ssh   = string
  })
  default = {
    admin = "test-admin.piviki.fi"
    api   = "test-api.piviki.fi"
    ssh   = "ssh-test.piviki.fi"
  }

  # The naming rule core and the deploy checks apply (AD-17): every test host's first label is
  # `test` or starts `test-`. The deploy SSH host follows the Hosts convention, ssh-test.
  validation {
    condition = alltrue([
      for host in [var.hosts.admin, var.hosts.api] :
      can(regex("^test(-[a-z0-9-]+)?\\.", host))
    ]) && can(regex("^ssh-test\\.", var.hosts.ssh))
    error_message = "Test's admin and api hosts must start test. or test-, and its SSH host ssh-test."
  }
}
