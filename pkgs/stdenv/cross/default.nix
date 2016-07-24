{ allPackages, crossSystem, config, ... } @ args:

rec {
  vanillaStdenv = import ../. (args // {
    crossSystem = null;
    # boot packages are not cross: build = host
    allPackages = args: allPackages ({ crossSystem = null; } // args);
    # No custom stdenvs when cross-compiling.
    # Not sure this is necessary, but this is how it worked before.
    config = builtins.removeAttrs config [ "replaceStdenv" ];
  }) // {
    cross = crossSystem;
  };

  buildPackages = allPackages {
    # It's OK to change the built-time dependencies
    allowCustomOverrides = true;
    stdenv = vanillaStdenv;
  };

  stdenvCross = with buildPackages;
    makeStdenvCross stdenv crossSystem binutilsCross gccCrossStageFinal;
}
