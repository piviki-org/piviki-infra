output "tunnel_id" {
  description = "GitHub Environment test variable CF_TUNNEL_ID."
  value       = module.core_ingress.tunnel_id
}

output "tunnel_token" {
  description = "TUNNEL_TOKEN in /etc/piviki/cloudflared.env on the test host."
  value       = module.core_ingress.tunnel_token
  sensitive   = true
}

output "deploy_service_token" {
  description = "GitHub Environment test secrets CF_ACCESS_DEPLOY_CLIENT_ID / _SECRET."
  value       = module.core_ingress.deploy_service_token
  sensitive   = true
}
