{
  config,
  lib,
  pkgs,
  ...
}:

let
  makeModularServiceWrapper = import ../../../lib/make-modular-service-wrapper.nix { inherit lib; };
  cfg = config.services.autobrr;
in
{
  imports = [
    (makeModularServiceWrapper {
      name = "autobrr";
      package = pkgs.autobrr;
      enableOption = lib.mkEnableOption "Autobrr";
    })
  ];

  options.services.autobrr.openFirewall = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Open ports in the firewall for the Autobrr web interface.";
  };

  config = lib.mkIf cfg.enable {
    networking.firewall = lib.mkIf cfg.openFirewall { allowedTCPPorts = [ cfg.settings.port ]; };
  };
}
