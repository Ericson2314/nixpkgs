{ system, bootStdenv, crossSystem, config, platform, lib, mkPackages, pkgs }:

let
  vanillaStdenv = import ../stdenv {
    inherit system platform config crossSystem lib;
    allPackages = args: import ../.. ({ inherit config system; } // args);
  };

  changer = config.replaceStdenv or null;

in rec {
  defaultStdenv = vanillaStdenv // { inherit platform; };

  stdenv =
    if bootStdenv != null then
      (bootStdenv // { inherit platform; })
    else if crossSystem == null && changer != null then
      changer {
        # We import again all-packages to avoid recursivities.
        pkgs = mkPackages {
          # We remove packageOverrides to avoid recursivities
          config = removeAttrs config [ "replaceStdenv" ];
        };
      }
    else
       defaultStdenv;
}
