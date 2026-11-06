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

  # Production's state lives in production's own private R2 bucket (EU jurisdiction); test has its
  # own bucket, so test's credentials cannot reach this state.
  # Bucket, key and endpoint come from backend.hcl (see backend.hcl.example):
  #   tofu init -backend-config=backend.hcl
  # R2 credentials come from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (r2-tofu-state-token-prod,
  # scoped to that bucket only); this is R2's S3 API, not AWS.
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
  # TF_VAR_state_passphrase, kept in the shared password manager (docs/secrets-inventory.md).
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
