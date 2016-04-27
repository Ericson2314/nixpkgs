{ system, bootStdenv, crossSystem, config, platform, lib, mkPackages }:

let
  vanillaStdenv = import ../stdenv {
    inherit system platform config crossSystem lib;
    allPackages = args: import ../.. ({ inherit config system; } // args);
  };

  changer = config.replaceStdenv or null;

in rec {
  defaultStdenv = vanillaStdenv // { inherit platform; };

  stdenv =
    if bootStdenv != null
    then (bootStdenv // { inherit platform; })
    else defaultStdenv;
}
