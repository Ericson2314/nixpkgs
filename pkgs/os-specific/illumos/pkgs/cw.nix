{
  lib,
  mkDerivation,

  source,
  fetchpatch,

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

  patches = [
    (fetchpatch {
      name = "linux-support.patch";
      url = "https://github.com/illumos/illumos-gate/compare/${source.rev}...Ericson2314:illumos-gate:cw-hack.diff";
      hash = "sha256-HL21JPRrN2pwiLX4fY41t+6Z0CB9JLKEsbpGtLqwNs0=";
    })
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
