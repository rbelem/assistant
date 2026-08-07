***REMOVED***-----------------------------------------------------------------------------
***REMOVED*** Cloudflare DNS Records
***REMOVED***-----------------------------------------------------------------------------
***REMOVED*** Manages DNS records for the domain via the Cloudflare provider. The zone
***REMOVED*** already exists in the account — this config only manages records within it.
***REMOVED***
***REMOVED*** The cloudflare_api_token must have Zone:Read + Zone:DNS:Edit permissions.
***REMOVED***
***REMOVED*** Apex + www point to GitHub Pages (rbelem.github.io). Service subdomains
***REMOVED*** (hermes, status, n8n, auth) point to the Hetzner VPS IP. Mail records (MX,
***REMOVED*** SPF, DKIM cf2024-1) are owned by Cloudflare Email Routing and excluded
***REMOVED*** (API rejects edits with error 1046).
***REMOVED***-----------------------------------------------------------------------------

***REMOVED***--- Zone lookup (zone already exists in the account) -------------------------
data "cloudflare_zone" "main" {
  name = var.domain_name
}

***REMOVED***--- Apex + www → GitHub Pages -----------------------------------------------
***REMOVED*** CNAME flattening at the apex; proxied so Cloudflare edge handles TLS.

resource "cloudflare_record" "apex" {
  zone_id = data.cloudflare_zone.main.id
  name    = var.domain_name
  type    = "CNAME"
  content = "rbelem.github.io"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "www" {
  zone_id = data.cloudflare_zone.main.id
  name    = "www"
  type    = "CNAME"
  content = "rbelem.github.io"
  proxied = true
  ttl     = 1
}

***REMOVED***--- VPS A records (agent services) ------------------------------------------
***REMOVED*** DNS-only (proxied=false) — Caddy on the VPS terminates TLS directly.

resource "cloudflare_record" "subdomains" {
  for_each = toset(var.subdomains)
  zone_id  = data.cloudflare_zone.main.id
  name     = each.value
  type     = "A"
  content  = hcloud_server.agent.ipv4_address
  proxied  = false
  ttl      = 600
}

***REMOVED***--- Remaining A/CNAME records -----------------------------------------------

resource "cloudflare_record" "c" {
  zone_id = data.cloudflare_zone.main.id
  name    = "c"
  type    = "A"
  content = "35.238.112.48"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "autoconfig" {
  zone_id = data.cloudflare_zone.main.id
  name    = "autoconfig"
  type    = "CNAME"
  content = "mailbox.org"
  proxied = false
  ttl     = 1
}

***REMOVED***--- CAA record -------------------------------------------------------------

resource "cloudflare_record" "caa" {
  zone_id = data.cloudflare_zone.main.id
  name    = "*"
  type    = "CAA"
  ttl     = 1
  data {
    flags = 0
    tag   = "issue"
    value = "letsencrypt.org"
  }
}

***REMOVED***--- SRV records ------------------------------------------------------------

resource "cloudflare_record" "srv_autodiscover" {
  zone_id = data.cloudflare_zone.main.id
  name    = "_autodiscover._tcp"
  type    = "SRV"
  ttl     = 1
  data {
    priority = 0
    weight   = 0
    port     = 443
    target   = "mailbox.org"
  }
}

resource "cloudflare_record" "srv_matrix_identity" {
  zone_id = data.cloudflare_zone.main.id
  name    = "_matrix-identity._tcp"
  type    = "SRV"
  ttl     = 1
  data {
    priority = 10
    weight   = 0
    port     = 443
    target   = "matrix.REDACTED-DOMAIN"
  }
}

***REMOVED***--- TXT records ------------------------------------------------------------
***REMOVED*** NOTE: the apex SPF record (v=spf1 include:_spf.mx.cloudflare.net), the 3
***REMOVED*** MX records (amir/linda/isaac.mx.cloudflare.net), and the DKIM record
***REMOVED*** cf2024-1._domainkey are managed by Cloudflare Email Routing — the API
***REMOVED*** rejects tofu modifications (error 1046). They are excluded from this
***REMOVED*** config; manage them via the Email Routing dashboard.

resource "cloudflare_record" "txt_dmarc" {
  zone_id = data.cloudflare_zone.main.id
  name    = "_dmarc"
  type    = "TXT"
  content = "v=DMARC1;p=none;rua=mailto:postmaster@REDACTED-DOMAIN;ruf=mailto:me@REDACTED-DOMAIN"
  ttl     = 1
}

resource "cloudflare_record" "txt_verification" {
  zone_id = data.cloudflare_zone.main.id
  name    = "72898689701e0f76504f75fe112289f5deca5ef0"
  type    = "TXT"
  content = "1f2788dc13e405f4e447241bc8e372fc78b583c0"
  ttl     = 1
}

resource "cloudflare_record" "txt_dkim_mbo0001" {
  zone_id = data.cloudflare_zone.main.id
  name    = "mbo0001._domainkey"
  type    = "TXT"
  ***REMOVED*** Concatenated from the two quoted strings in the zone export.
  content = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2K4PavXoNY8eGK2u61LIQlOHS8f5sWsCK5b+HMOfo0M+aNHwfqlVdzi/IwmYnuDKuXYuCllrgnxZ4fG4yVaux58v9grVsFHdzdjPlAQfp5rkiETYpCMZwgsmdseJ4CoZaosPHLjPumFE/Ua2WAQQljnunsM9TONM9L6KxrO9t5IISD1XtJb0bq1lVI/e72k3mnPd/q77qzhTDmwN4TSNJZN8sxzUJx9HNSMRRoEIHSDLTIJUK+Up8IeCx0B7CiOzG5w/cHyZ3AM5V8lkqBaTDK46AwTkTVGJf59QxUZArG3FEH5vy9HzDmy0tGG+053/x4RqkhqMg5/ClDm+lpZqWwIDAQAB"
  ttl     = 1
}