{ allPackages, config, ... } @ args:

rec {
  vanillaStdenv = (import ../. (args // {
    # Remove config.replaceStdenv to ensure termination.
    config = builtins.removeAttrs config [ "replaceStdenv" ];
  })).stdenv;

  buildPackages = allPackages {
    # It's OK to change the built-time dependencies
    allowCustomOverrides = true;
    stdenv = vanillaStdenv;
  };

  stdenvCustom = config.replaceStdenv { pkgs = buildPackages; };
}
