{
  mkDerivation,

  illumosSetupHook,
  make,
  install,
}:

# libtsol ships <tsol/label.h>, which head/zone.h includes. Only the header is
# wanted here, not the library.
mkDerivation {
  name = "libtsol-headers";
  path = "usr/src/lib/libtsol";
  noCC = true;

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/Makefile.msg.targ"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    install
    make
  ];

  headersOnly = true;

  # libtsol overrides ROOTHDRDIR to .../include/tsol, and install(1) will not
  # create that directory itself.
  installPhase = ''
    mkdir -p "$out/include/tsol"
    includesPhase
  '';
}
