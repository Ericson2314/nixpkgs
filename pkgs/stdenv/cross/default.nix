{ system, allPackages, platform, crossSystem, config, ... } @ args:

rec {
  vanillaStdenv = import ../. (args // {
    crossSystem = null;
    # No custom stdenvs when cross-compiling.
    # Not sure this is necessary, but this is how it worked before.
    config = builtins.removeAttrs config [ "replaceStdenv" ];
  }) // {
    cross = crossSystem;
  };

  buildPackages = allPackages {
    # It's OK to change the built-time dependencies
    allowCustomOverrides = true;
    bootStdenv = vanillaStdenv;
    inherit system platform crossSystem config;
  };

  stdenvCross = with buildPackages;
    makeStdenvCross stdenv crossSystem binutilsCross gccCrossStageFinal;
}
