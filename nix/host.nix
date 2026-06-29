{ pkgs, inputs, ... }: {
  imports = [
    ./k3s.nix
    ./caddy.nix
    ./firewall.nix
    ./tailscale.nix
    ./backup.nix
    ./secrets.nix
  ];

  ***REMOVED*** Nix
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  ***REMOVED*** SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  ***REMOVED*** User
  users.users.rodrigo = {
    isNormalUser = true;
    shell = pkgs.bash;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      ***REMOVED*** Fetch from GitHub
      ***REMOVED*** Run: curl -sL https://github.com/rbelem.keys
      ***REMOVED*** Paste the keys here for offline builds
    ];
  };

  ***REMOVED*** Allow running unpatched binaries
  programs.nix-ld.enable = true;

  ***REMOVED*** Locale
  i18n.defaultLocale = "en_GB.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "pt_BR.UTF-8";
    LC_IDENTIFICATION = "pt_BR.UTF-8";
    LC_MEASUREMENT = "pt_BR.UTF-8";
    LC_MONETARY = "pt_BR.UTF-8";
    LC_NAME = "pt_BR.UTF-8";
    LC_NUMERIC = "pt_BR.UTF-8";
    LC_PAPER = "pt_BR.UTF-8";
    LC_TELEPHONE = "pt_BR.UTF-8";
    LC_TIME = "pt_BR.UTF-8";
  };

  ***REMOVED*** Timezone
  time.timeZone = "REDACTED-TZ";

  ***REMOVED*** State version
  system.stateVersion = "24.11";
}
