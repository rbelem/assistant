{ pkgs, ... }: {
  ***REMOVED*** Caddy reverse proxy with Porkbun DNS-01 wildcard TLS
  ***REMOVED*** Caddy runs on the host and proxies to k8s services via NodePort.
  ***REMOVED*** Wildcard cert for *.REDACTED-DOMAIN obtained via Porkbun DNS challenge.
  services.caddy = {
    enable = true;

    ***REMOVED*** Porkbun API credentials for DNS-01 challenge
    environmentFile = "/etc/caddy/env";

    ***REMOVED*** Global config: DNS-01 challenge via Porkbun, wildcard cert
    extraConfig = ''
      (dns01) {
        tls {
          dns porkbun {env.PORKBUN_API_KEY} {env.PORKBUN_SECRET_API_KEY}
        }
      }
    '';

    ***REMOVED*** Hermes — AI agent backend (k8s NodePort 30080)
    virtualHosts."hermes.REDACTED-DOMAIN".extraConfig = ''
      import dns01
      reverse_proxy localhost:30080
    '';

    ***REMOVED*** Uptime Kuma — monitoring dashboard (k8s NodePort 30001)
    virtualHosts."status.REDACTED-DOMAIN".extraConfig = ''
      import dns01
      reverse_proxy localhost:30001
    '';

    ***REMOVED*** n8n — Tailscale-gated
    virtualHosts."n8n.REDACTED-DOMAIN".extraConfig = ''
      import dns01
      @tailscale remote_ip 100.64.0.0/10 100.128.0.0/10
      handle @tailscale {
        reverse_proxy localhost:30002
      }
      handle {
        respond "Access denied" 403
      }
    '';

    ***REMOVED*** Zitadel — Tailscale-gated
    virtualHosts."auth.REDACTED-DOMAIN".extraConfig = ''
      import dns01
      @tailscale remote_ip 100.64.0.0/10 100.128.0.0/10
      handle @tailscale {
        reverse_proxy localhost:30003
      }
      handle {
        respond "Access denied" 403
      }
    '';
  };

  ***REMOVED*** Ensure Caddy environment file exists
  systemd.services.caddy.serviceConfig.EnvironmentFile = "/etc/caddy/env";

  ***REMOVED*** Create directory for Caddy env
  systemd.tmpfiles.rules = [
    "d /etc/caddy 0700 root root -"
  ];

  ***REMOVED*** Allow HTTP/HTTPS
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
