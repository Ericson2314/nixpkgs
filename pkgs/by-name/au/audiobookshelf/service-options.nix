# Options for the audiobookshelf modular service.
# Used by both service.nix and the NixOS compat wrapper.
{ lib, ... }:

{
  options = {
    package = lib.options.mkModularPackageOption "audiobookshelf" { };

    dataDir = lib.mkOption {
      description = "Path to Audiobookshelf config and metadata inside of /var/lib.";
      default = "audiobookshelf";
      type = lib.types.str;
    };

    host = lib.mkOption {
      description = "The host Audiobookshelf binds to.";
      default = "127.0.0.1";
      example = "0.0.0.0";
      type = lib.types.str;
    };

    port = lib.mkOption {
      description = "The TCP port Audiobookshelf will listen on.";
      default = 8000;
      type = lib.types.port;
    };

    user = lib.mkOption {
      description = "User account under which Audiobookshelf runs.";
      default = "audiobookshelf";
      type = lib.types.str;
    };

    group = lib.mkOption {
      description = "Group under which Audiobookshelf runs.";
      default = "audiobookshelf";
      type = lib.types.str;
    };
  };
}
