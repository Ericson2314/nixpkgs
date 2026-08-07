{
  lib,
  mkDerivation,

  #illumosSetupHook,
  #make,
  #install,
}:

mkDerivation {
  noCC = true;

  path = "usr/src/cmd/sgs/lorder";
  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.smatch"
    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"
    "usr/src/cmd/sgs/Makefile.com"
  ];

  preInstall = ''
    mkdir -p $out/bin
  '';

  #nativeBuildInputs = [
  #  illumosSetupHook
  #  make
  #  install
  #];

  meta.platforms = lib.platforms.unix;
}
