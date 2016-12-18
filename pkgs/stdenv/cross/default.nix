{ lib
, system, platform, crossSystem, config
}:

let
  bootStages = import ../. {
    inherit lib system platform;
    crossSystem = null;
    # Ignore custom stdenvs when cross compiling for compatability
    config = builtins.removeAttrs config [ "replaceStdenv" ];
  };

in bootStages ++ [

  # Build Packages
  (vanillaPackages: {
    inherit system platform config;
    crossSystem = null;
    # Should be false, but we're trying to preserve hashes for now
    selfBuild = true;
    # It's OK to change the built-time dependencies
    allowCustomOverrides = true;
    stdenv = vanillaPackages.stdenv // {
      # Needed elsewhere as a hacky way to pass the target
      cross = crossSystem;
      overrides = _: _: {};
    };
  })

  # Run Packages
  (buildPackages: {
    inherit system platform crossSystem config;
    selfBuild = false;
    stdenv = if crossSystem.useiOSCross or false
      then let
          inherit (buildPackages.darwin.ios-cross {
              prefix = crossSystem.config;
              inherit (crossSystem) arch;
              simulator = crossSystem.isiPhoneSimulator or false; })
            cc binutils;
        in buildPackages.makeStdenvCross
          buildPackages.stdenv crossSystem
          binutils cc
      else buildPackages.makeStdenvCross
        buildPackages.stdenv crossSystem
        buildPackages.binutilsCross buildPackages.gccCrossStageFinal;
  })

]
