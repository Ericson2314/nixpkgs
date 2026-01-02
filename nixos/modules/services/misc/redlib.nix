{
  config,
  lib,
  pkgs,
  ...
}:

let
  makeModularServiceWrapper = import ../../../lib/make-modular-service-wrapper.nix { inherit lib; };
  cfg = config.services.redlib;
in
{
  imports = [
    (lib.mkRenamedOptionModule
      [ "services" "libreddit" ]
      [ "services" "redlib" ]
    )
    (makeModularServiceWrapper {
      name = "redlib";
      package = pkgs.redlib;
      enableOption = lib.mkEnableOption "private front-end for Reddit";
      meta.maintainers = with lib.maintainers; [ Guanran928 ];
    })
  ];

  options.services.redlib.openFirewall = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Open ports in the firewall for the redlib web interface";
  };

  config = lib.mkIf cfg.enable {
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
