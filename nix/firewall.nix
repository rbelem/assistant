{ ... }: {
  networking.firewall = {
    enable = true;

    allowedTCPPorts = [
      22    ***REMOVED*** SSH
      80    ***REMOVED*** HTTP
      443   ***REMOVED*** HTTPS
      6443  ***REMOVED*** k3s API
    ];

    allowedUDPPorts = [
      51820 ***REMOVED*** Tailscale WireGuard
    ];

    ***REMOVED*** Allow ICMP (ping)
    allowedPingTypes = [ "echo-request" ];

    ***REMOVED*** Trust Tailscale interface — allow all traffic over VPN
    trustedInterfaces = [ "tailscale0" ];

    ***REMOVED*** k3s internal ranges
    extraCommands = ''
      ***REMOVED*** Allow pod-to-pod and service traffic
      iptables -A INPUT -s 10.42.0.0/16 -j ACCEPT
      iptables -A INPUT -s 10.43.0.0/16 -j ACCEPT
    '';
  };
}
