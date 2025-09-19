{
  lib,
  mkDerivation,

  source,
  fetchpatch,

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

  patches = [
    (fetchpatch {
      name = "linux-support.patch";
      url = "https://github.com/illumos/illumos-gate/compare/${source.rev}...Ericson2314:illumos-gate:247005e13a05f4973de52122bc82074a23f62087.diff";
      hash = "sha256-fCp2blv+2fgcM7ldWCJPCM4NQXAUkL7Kw7AQKJjtFrI=";
    })
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
