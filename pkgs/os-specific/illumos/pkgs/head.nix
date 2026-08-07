{
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  rpcgen,
}:
mkDerivation {
  name = "head";
  path = "usr/src/head";
  noCC = true;

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    install
    make
    rpcgen
  ];

  headersOnly = true;
}
