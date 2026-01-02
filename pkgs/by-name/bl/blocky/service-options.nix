# Options for the blocky modular service.
# Used by both service.nix and the NixOS compat wrapper.
{ lib, pkgs, ... }:

{
  options = {
    package = lib.options.mkModularPackageOption "blocky" { };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = (pkgs.formats.yaml { }).type;
      };
      default = { };
      description = ''
        Blocky configuration. Refer to
        <https://0xerr0r.github.io/blocky/configuration/>
        for details on supported values.
      '';
    };
  };
}
