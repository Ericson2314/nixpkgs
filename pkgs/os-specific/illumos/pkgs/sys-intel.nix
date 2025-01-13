{
  mkDerivation,

  source,
  fetchpatch,

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

  patches = [
    (fetchpatch {
      name = "linux-support.patch";
      url = "https://github.com/illumos/illumos-gate/compare/${source.rev}...Ericson2314:illumos-gate:headers-hack.diff";
      hash = "sha256-TgwhFFjf+nmh7/KXrFi6ieTXLQAunLn7Zinmxrc1GGc=";
    })
  ];

  nativeBuildInputs = [
    illumosSetupHook
    install
    make
    nawk
  ];

  headersOnly = true;
}
