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

  # Test's own state: its own key in the private R2 bucket (EU jurisdiction) and its own
  # passphrase, never production's (AD-17). Bucket, key and endpoint come from backend.hcl
  # (see backend.hcl.example):
  #   tofu init -backend-config=backend.hcl
  # R2 credentials come from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (an R2 API token scoped to
  # that bucket); this is R2's S3 API, not AWS.
  backend "s3" {
    region                      = "auto"
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_lockfile                = true
  }

  # Every state and plan is encrypted before it leaves the machine. The passphrase is
  # TF_VAR_state_passphrase, test's own, kept in Bitwarden's test collection
  # (docs/secrets-inventory.md).
  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }
    state {
      method   = method.aes_gcm.state
      enforced = true
    }
    plan {
      method   = method.aes_gcm.state
      enforced = true
    }
  }
}

provider "cloudflare" {
  # CLOUDFLARE_API_TOKEN from the environment; see docs/runbook-first-deploy.md for its scopes.
}
