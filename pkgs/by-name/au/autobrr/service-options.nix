# Options for the autobrr modular service.
# Used by both service.nix and the NixOS compat wrapper.
{ lib, ... }:

{
  options = {
    package = lib.options.mkModularPackageOption "autobrr" { };

    secretFile = lib.mkOption {
      type = lib.types.path;
      description = "File containing the session secret for the Autobrr web interface.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {
        host = "127.0.0.1";
        port = 7474;
        checkForUpdates = true;
      };
      example = {
        logLevel = "DEBUG";
      };
      description = ''
        Autobrr configuration options.

        Refer to <https://autobrr.com/configuration/autobrr>
        for a full list.
      '';
    };
  };
}
