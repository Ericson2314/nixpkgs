{
  mkDerivation,

  source,
  fetchpatch,

  cw,

  libelf,
}:

mkDerivation {
  pname = "mcs";

  path = "usr/src/cmd/sgs/mcs/amd64";
  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.smatch"
    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"
    "usr/src/cmd/sgs/Makefile.com"
    "usr/src/cmd/sgs/mcs"
    "usr/src/cmd/sgs/mcs/Makefile.targ"
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
    #"ROOTONBLD=${builtins.placeholder "out"}"
    #"ROOTONBLDMAN1ONBLD=${builtins.placeholder "man"}/man/man1"
  ];

  extraNativeBuildInputs = [
    cw
  ];

  #buildInputs = [
  #  libelf
  #];

  preInstall = ''
    mkdir -p $out/bin $man/man/man1
  '';

  #hardeningDisable = [ "format" ];
}
