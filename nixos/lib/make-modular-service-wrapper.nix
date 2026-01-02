# Helper to create NixOS compat wrappers for modular services.
#
# Usage:
#   makeModularServiceWrapper {
#     name = "redlib";
#     package = pkgs.redlib;  # Must have .serviceOptions and .services.default
#   }
#
# Additional NixOS-specific options and config can be defined separately
# in the module - they will not be forwarded to the service.
{ lib }:

{
  # Name of the service (used for services.<name> and system.services.<name>)
  name,

  # The package that provides .serviceOptions and .services.default
  package,

  # The enable option (defaults to mkEnableOption with package description)
  enableOption ? lib.mkEnableOption (package.meta.description or "the ${name} service"),

  # Optional module meta (maintainers, etc.)
  meta ? { },
}:

{ config, pkgs, ... }:

let
  cfg = config.services.${name};
  # Get the option names from the service module to know what to forward
  serviceOptionNames = lib.attrNames (package.serviceOptions { inherit lib; }).options;
in
{
  options.services.${name} = lib.mkOption {
    type = lib.types.submodule {
      imports = [ package.serviceOptions ];
      options.enable = enableOption;
      config.package = lib.mkDefault package;
    };
    default = { };
    description = "Configuration for ${name}";
  };

  config = lib.mkIf cfg.enable {
    system.services.${name} = {
      imports = [ package.services.default ];
      # Only forward options that exist in the service module
      thisService = lib.filterAttrs (n: _: builtins.elem n serviceOptionNames) cfg;
    };
  };

  inherit meta;
}
