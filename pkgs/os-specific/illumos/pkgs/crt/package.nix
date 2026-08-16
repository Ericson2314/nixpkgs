{
  lib,
  mkDerivation,

  illumosSetupHook,
  make,
  cw,

  install,
  headers,
}:

mkDerivation {
  name = "crt-amd64";
  noLibc = true;
  path = "usr/src/lib/crt/amd64";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/crt"

    "usr/src/lib/libc/inc/xpg6.h"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    cw
    install
  ];

  buildInputs = [ headers ];

  preInstall = ''
    mkdir -p $out/lib
  '';
}
