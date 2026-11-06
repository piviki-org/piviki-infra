# Offline (mocked providers, no backend, no credentials): test's state holds only test-named
# resources on test hosts, and no shared one (AD-17), so `plan -destroy` on it can remove nothing
# production or the coming-soon page uses. The founder's real `plan -destroy` (runbook §2.3)
# confirms the same against Cloudflare.
mock_provider "cloudflare" {}
mock_provider "random" {}

variables {
  state_passphrase         = "offline-test-passphrase-0123456789abcdef"
  account_id               = "acc"
  zone_id                  = "zone-from-prod-output"
  otp_identity_provider_id = "otp-from-prod-output"
  access_team_name         = "team"
  librarian_emails         = ["founder@example.org"]
}

run "before_seeding" {
  command = plan

  assert {
    condition     = module.core_ingress.tunnel_id != null
    error_message = "the test Tunnel is planned"
  }
}

run "plans_with_public_records" {
  command = plan

  variables {
    public_records_enabled = true
  }
}

run "refuses_a_production_host" {
  command = plan

  variables {
    hosts = { admin = "admin.piviki.fi", api = "test-api.piviki.fi", ssh = "ssh-test.piviki.fi" }
  }

  expect_failures = [var.hosts]
}
