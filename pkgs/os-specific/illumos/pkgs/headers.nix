{
  lib,
  stdenvNoLibc,
  symlinkJoin,
  head,
  sys,
  version,
}:

symlinkJoin rec {
  name = "${pname}-${version}";
  pname = "headers-illumos";
  inherit version;

  paths = [
    head
    sys
  ];

  meta.platforms = lib.platforms.illumos;
}
