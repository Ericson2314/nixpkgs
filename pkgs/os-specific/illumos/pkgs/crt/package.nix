{
  lib,
  mkDerivation,

  source,
  fetchpatch,

  illumosSetupHook,
  make,
  cw,

  install,
  headers,
}:

mkDerivation {
  name = "crt-amd64";
  noLibc = true;
  path = "usr/src/lib/crt/amd64";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/crt"

    "usr/src/lib/libc/inc/xpg6.h"
  ];

  patches = [
    (fetchpatch {
      name = "linux-support.patch";
      url = "https://github.com/illumos/illumos-gate/compare/${source.rev}...Ericson2314:illumos-gate:libc-hack.diff";
      hash = "sha256-T0Cyy1Q1NPqocQA77bNpDnRp8PjuiV/9Bf6rg84aTTc=";
    })
    ../../patches/no-64-special-tools.patch
    ../../patches/clang-skip-flags.patch
    ./no-compat-links.patch
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    cw
    install
  ];

  buildInputs = [ headers ];

  preInstall = ''
    mkdir -p $out/lib
  '';
}
