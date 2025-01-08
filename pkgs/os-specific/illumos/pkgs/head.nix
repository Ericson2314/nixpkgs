{
  mkDerivation,

  source,
  fetchpatch,

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

  patches = [
    (fetchpatch {
      name = "linux-support.patch";
      url = "https://github.com/illumos/illumos-gate/compare/${source.rev}...Ericson2314:illumos-gate:headers-hack^.diff";
      hash = "sha256-fCp2blv+2fgcM7ldWCJPCM4NQXAUkL7Kw7AQKJjtFrI=";
    })
  ];

  nativeBuildInputs = [
    illumosSetupHook
    install
    make
    rpcgen
  ];

  headersOnly = true;
}
