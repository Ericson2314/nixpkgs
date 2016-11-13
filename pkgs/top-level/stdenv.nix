{ system, bootStdenv, crossSystem, config, platform, lib, nixpkgsFun }:

let
  allStdenvs = import ../stdenv {
    inherit system platform config crossSystem lib;
    allPackages = nixpkgsFun;
  };
in rec {
  defaultStdenv = allStdenvs.stdenv // { inherit platform; };

  stdenv =
    if bootStdenv != null
    then (bootStdenv // { inherit platform; })
    else defaultStdenv;
}
