{
  lib,
  stdenvNoLibc,
  symlinkJoin,
  head,
  uts-headers,
  sys-intel,
  libtsol-headers,

  #sys-i86pc,
  version,
}:

symlinkJoin rec {
  name = "${pname}-${version}";
  pname = "headers-illumos";
  inherit version;

  paths = [
    head
    uts-headers
    sys-intel
    libtsol-headers

    #sys-i86pc
  ];

  meta.platforms = lib.platforms.illumos;
}
