{ lib, allPackages
, system, platform, crossSystem, config
}:

rec {
  vanillaStdenv = (import ../. {
    inherit lib allPackages system platform crossSystem;
    # Remove config.replaceStdenv to ensure termination.
    config = builtins.removeAttrs config [ "replaceStdenv" ];
  }).stdenv;

  buildPackages = allPackages {
    # It's OK to change the built-time dependencies
    allowCustomOverrides = true;
    stdenv = vanillaStdenv;
    inherit system platform crossSystem config;
  };

  stdenvCustom = config.replaceStdenv { pkgs = buildPackages; };
}
