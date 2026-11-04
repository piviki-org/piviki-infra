output "tunnel_id" {
  description = "GitHub Environment variable CF_TUNNEL_ID."
  value       = cloudflare_zero_trust_tunnel_cloudflared.env.id
}

output "tunnel_token" {
  description = "TUNNEL_TOKEN in /etc/piviki/cloudflared.env on the host."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.env.token
  sensitive   = true
}

output "deploy_service_token" {
  description = "GitHub Environment secrets CF_ACCESS_DEPLOY_CLIENT_ID / _SECRET."
  value = {
    client_id     = cloudflare_zero_trust_access_service_token.deploy.client_id
    client_secret = cloudflare_zero_trust_access_service_token.deploy.client_secret
  }
  sensitive = true
}

output "checks_service_token" {
  description = "GitHub Environment secrets CF_ACCESS_CHECKS_CLIENT_ID / _SECRET."
  value = {
    client_id     = cloudflare_zero_trust_access_service_token.checks.client_id
    client_secret = cloudflare_zero_trust_access_service_token.checks.client_secret
  }
  sensitive = true
}
