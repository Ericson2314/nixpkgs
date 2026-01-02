# Options for the redlib modular service.
# Used by both service.nix and the NixOS compat wrapper.
{ lib, ... }:

{
  options = {
    package = lib.options.mkModularPackageOption "redlib" { };

    address = lib.mkOption {
      default = "0.0.0.0";
      example = "127.0.0.1";
      type = lib.types.str;
      description = "The address to listen on";
    };

    port = lib.mkOption {
      default = 8080;
      example = 8000;
      type = lib.types.port;
      description = "The port to listen on";
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType =
          with lib.types;
          attrsOf (
            nullOr (oneOf [
              bool
              int
              str
            ])
          );
        options = { };
      };
      default = { };
      description = ''
        See [GitHub](https://github.com/redlib-org/redlib/tree/main?tab=readme-ov-file#configuration) for available settings.
      '';
    };
  };
}
