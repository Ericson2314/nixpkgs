{
  lib,
  stdenvNoLibc,
  symlinkJoin,
  head,
  sys,
  sys-intel,
  #sys-i86pc,
  version,
}:

symlinkJoin rec {
  name = "${pname}-${version}";
  pname = "headers-illumos";
  inherit version;

  paths = [
    head
    sys
    sys-intel
    #sys-i86pc
  ];

  meta.platforms = lib.platforms.illumos;
}
