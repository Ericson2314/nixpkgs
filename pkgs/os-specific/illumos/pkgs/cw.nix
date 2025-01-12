{
  mkDerivation,

  source,
  fetchpatch,

  pkg-config,
  ninja,
  rpcsvc-proto,

  libtirpc,
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
      hash = "sha256-6D5f5PyWTqLpQZrMc1n1iW2XcrE8PNdcv714dK0ZZo0=";
    })
  ];

  makeFlags = [
    "ROOTONBLD=${builtins.placeholder "out"}"
    "ROOTONBLDMAN1ONBLD=${builtins.placeholder "man"}/man/man1"
  ];

  preInstall = ''
    mkdir -p $out/bin $man/man/man1
  '';

  #hardeningDisable = [ "format" ];
}
