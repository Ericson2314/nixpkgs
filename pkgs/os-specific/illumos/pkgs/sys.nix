{
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  nawk,
}:
mkDerivation {
  name = "sys";
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

  nativeBuildInputs = [
    illumosSetupHook
    install
    make
    nawk
  ];

  headersOnly = true;
}
