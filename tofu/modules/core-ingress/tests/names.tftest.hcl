# Offline (mocked providers, no credentials): every resource the module plans carries the calling
# environment's name or host, and the zone and login method are used only by the ids passed in
# (AD-17). Run: tofu -chdir=tofu/modules/core-ingress init -backend=false && tofu ... test
mock_provider "cloudflare" {}
mock_provider "random" {}

variables {
  name                     = "piviki-test"
  account_id               = "acc"
  zone_id                  = "zone-from-prod-output"
  otp_identity_provider_id = "otp-from-prod-output"
  access_team_name         = "team"
  librarian_emails         = ["founder@example.org"]
  hosts                    = { admin = "test-admin.piviki.fi", api = "test-api.piviki.fi", ssh = "ssh-test.piviki.fi" }
  public_records_enabled   = true
}

run "every_resource_is_named_for_the_environment" {
  command = plan

  assert {
    condition = alltrue([
      cloudflare_zero_trust_tunnel_cloudflared.env.name == "piviki-test",
      cloudflare_zero_trust_access_service_token.deploy.name == "piviki-test-deploy",
      startswith(cloudflare_zero_trust_access_policy.librarians.name, "piviki-test "),
      startswith(cloudflare_zero_trust_access_policy.deploy.name, "piviki-test "),
      startswith(cloudflare_zero_trust_access_application.admin.name, "piviki-test "),
      startswith(cloudflare_zero_trust_access_application.ssh.name, "piviki-test "),
    ])
    error_message = "a resource is not named for piviki-test"
  }

  assert {
    condition = (
      cloudflare_dns_record.ssh.name == "ssh-test.piviki.fi" &&
      cloudflare_dns_record.admin[0].name == "test-admin.piviki.fi" &&
      cloudflare_dns_record.api[0].name == "test-api.piviki.fi"
    )
    error_message = "a record is not on a test host"
  }

  assert {
    condition = alltrue([
      for r in [cloudflare_dns_record.ssh, cloudflare_dns_record.admin[0], cloudflare_dns_record.api[0]] :
      r.zone_id == "zone-from-prod-output"
    ])
    error_message = "records must use the zone id passed in"
  }

  assert {
    condition     = tolist(cloudflare_zero_trust_access_application.admin.allowed_idps) == tolist(["otp-from-prod-output"])
    error_message = "admin must use the login method id passed in"
  }
}

run "no_public_records_before_seeding" {
  command = plan

  variables {
    public_records_enabled = false
  }

  assert {
    condition     = length(cloudflare_dns_record.admin) == 0 && length(cloudflare_dns_record.api) == 0
    error_message = "admin/api records must wait for the seed (AD-5)"
  }
}
