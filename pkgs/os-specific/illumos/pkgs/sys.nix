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
  name = "include";
  path = "usr/src/uts/common/sys";
  noCC = true;

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"
    "usr/src/Makefile.psm"

    "usr/src/uts/Makefile.uts"
    "usr/src/uts/common/os/privs.awk"
    "usr/src/uts/common/os/priv_defs"
    "usr/src/uts/common/io/usb/usbdevs2h.awk"
    "usr/src/uts/common/io/usb/usbdevs"
  ];

  patches = [
    (fetchpatch {
      name = "linux-support.patch";
      url = "https://github.com/illumos/illumos-gate/compare/${source.rev}...Ericson2314:illumos-gate:headers-hack.diff";
      hash = "sha256-fCp2blv+2fgcM7ldWCJPCM4NQXAUkL7Kw7AQKJjtFrI=";
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
