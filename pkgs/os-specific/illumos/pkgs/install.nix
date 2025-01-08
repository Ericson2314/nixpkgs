{
  lib,
  mkDerivation,

  source,
  fetchpatch,

  illumosSetupHook,
  make,
  install,
  cw,
}:

mkDerivation {
  pname = "install";

  path = "usr/src/tools/install.bin";
  extraPaths = [
    "usr/src/tools/Makefile"
    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"
    "usr/src/tools/protocmp/stdusers.h"
    "usr/src/tools/protocmp/stdusers.c"
    "usr/src/Makefile.master"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"
    "usr/src/lib/libgen/common/mkdirp.c"
  ];

  outputs = [
    "out"
    "man"
  ];

  patches = [
    (fetchpatch {
      name = "linux-support.patch";
      url = "https://github.com/illumos/illumos-gate/compare/${source.rev}...Ericson2314:illumos-gate:install-hack.diff";
      hash = "sha256-493EKAkJA/MyU70MbTWUv2vRv50eClAxfaa+rJYV4TE=";
    })
  ];

  makeFlags = [
    "ROOTONBLD=${builtins.placeholder "out"}"
    "ROOTONBLDMAN1ONBLD=${builtins.placeholder "man"}/man/man1"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    cw
  ];

  preInstall = ''
    mkdir -p $out/bin $man/man/man1
  '';

  meta.platforms = lib.platforms.unix;
}
