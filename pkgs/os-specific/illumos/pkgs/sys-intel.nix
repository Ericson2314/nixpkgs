{
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  nawk,
}:
mkDerivation {
  name = "sys-intel";
  path = "usr/src/uts/intel/sys";
  noCC = true;

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"
    "usr/src/Makefile.psm"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    install
    make
    nawk
  ];

  headersOnly = true;
}
