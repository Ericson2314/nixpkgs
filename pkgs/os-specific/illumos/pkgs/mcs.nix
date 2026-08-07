{
  mkDerivation,

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
