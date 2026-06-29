{ ... }: {
  ***REMOVED*** Caddy reverse proxy
  ***REMOVED*** Caddy runs on the host and proxies to k8s services via NodePort.
  ***REMOVED*** This avoids needing k8s DNS resolution from the host.
  services.caddy = {
    enable = true;

    virtualHosts."agent.REDACTED-DOMAIN".extraConfig = ''
      ***REMOVED*** Hermes — AI agent backend (k8s NodePort 30080)
      reverse_proxy localhost:30080

      ***REMOVED*** Headroom — token compression proxy (k8s NodePort 30878)
      handle_path /headroom/* {
        reverse_proxy localhost:30878
      }

      ***REMOVED*** Uptime Kuma — monitoring dashboard (k8s NodePort 30001)
      handle_path /monitor/* {
        reverse_proxy localhost:30001
      }
    '';

    ***REMOVED*** Tailscale-only admin endpoint
    ***REMOVED*** Only reachable over Tailscale (DNS points to Tailscale IP)
    virtualHosts."admin.agent.REDACTED-DOMAIN".extraConfig = ''
      ***REMOVED*** k3s dashboard / Node metrics (if exposed)
      respond "Admin panel coming soon" 200
    '';
  };

  ***REMOVED*** Allow HTTP/HTTPS
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
