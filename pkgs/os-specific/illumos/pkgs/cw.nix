{
  lib,
  mkDerivation,

  illumosSetupHook,
  make,
}:

mkDerivation {
  pname = "cw";

  path = "usr/src/tools/cw";
  extraPaths = [
    "usr/src/tools/Makefile"
    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"
    "usr/src/Makefile.master"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

  ];

  outputs = [
    "out"
    "man"
  ];

  makeFlags = [
    "ROOTONBLD=${builtins.placeholder "out"}"
    "ROOTONBLDMAN1ONBLD=${builtins.placeholder "man"}/man/man1"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
  ];

  preInstall = ''
    mkdir -p $out/bin $man/man/man1
  '';

  meta.platforms = lib.platforms.unix;
}
