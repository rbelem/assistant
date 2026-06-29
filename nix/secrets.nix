{ ... }: {
  ***REMOVED*** sops-nix for Nix-level secrets (k3s token, etc.)
  sops = {
    defaultSopsFile = ../secrets.yaml;
    age = {
      ***REMOVED*** Generate key: nix run nixpkgs***REMOVED***ssh-to-age -- -i /etc/ssh/ssh_host_ed25519_key
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      keyFile = "/etc/sops/age/key.txt";
    };
  };
}
