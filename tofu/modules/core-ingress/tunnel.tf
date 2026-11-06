# One Tunnel for this environment; its connector is the host's cloudflared. Ingress points the
# admin and api hosts at Caddy and the SSH host at the host's own sshd (AD-17).
resource "random_bytes" "tunnel_secret" {
  length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "env" {
  account_id    = var.account_id
  name          = var.name
  config_src    = "cloudflare"
  tunnel_secret = random_bytes.tunnel_secret.base64
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "env" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.env.id

  config = {
    ingress = [
      {
        hostname = var.hosts.admin
        service  = "http://caddy:80"
        origin_request = {
          # cloudflared itself refuses any request without a valid Access token for this app.
          access = {
            required  = true
            team_name = var.access_team_name
            aud_tag   = [cloudflare_zero_trust_access_application.admin.aud]
          }
        }
      },
      {
        hostname = var.hosts.api
        service  = "http://caddy:80"
      },
      {
        hostname = var.hosts.ssh
        service  = "ssh://host.docker.internal:22"
        origin_request = {
          access = {
            required  = true
            team_name = var.access_team_name
            aud_tag   = [cloudflare_zero_trust_access_application.ssh.aud]
          }
        }
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "env" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.env.id
}
