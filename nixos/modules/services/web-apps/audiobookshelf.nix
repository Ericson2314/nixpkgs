{
  config,
  lib,
  pkgs,
  ...
}:

let
  makeModularServiceWrapper = import ../../../lib/make-modular-service-wrapper.nix { inherit lib; };
  cfg = config.services.audiobookshelf;
in
{
  imports = [
    (makeModularServiceWrapper {
      name = "audiobookshelf";
      package = pkgs.audiobookshelf;
      enableOption = lib.mkEnableOption "Audiobookshelf, self-hosted audiobook and podcast server";
      meta.maintainers = with lib.maintainers; [ wietsedv ];
    })
  ];

  options.services.audiobookshelf.openFirewall = lib.mkOption {
    description = "Open ports in the firewall for the Audiobookshelf web interface.";
    default = false;
    type = lib.types.bool;
  };

  config = lib.mkIf cfg.enable {
    users.users = lib.mkIf (cfg.user == "audiobookshelf") {
      audiobookshelf = {
        isSystemUser = true;
        group = cfg.group;
        home = "/var/lib/${cfg.dataDir}";
      };
    };

    users.groups = lib.mkIf (cfg.group == "audiobookshelf") {
      audiobookshelf = { };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
