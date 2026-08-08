{
  mkDerivation,

  illumosSetupHook,
  make,
  install,
}:

# libscf ships <libscf.h> (the SMF service configuration facility), which
# libc's sys/uadmin.c includes. Only the headers are wanted here, not the
# library.
mkDerivation {
  name = "libscf-headers";
  path = "usr/src/lib/libscf";
  noCC = true;

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"
    "usr/src/Makefile.msg.targ"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    install
    make
  ];

  makeFlags = [
    "MACH=i386"
    "MACH64=amd64"
  ];

  headersOnly = true;

  # install(1) will not create the destination directory itself.
  installPhase = ''
    mkdir -p "$out/include"
    includesPhase
  '';
}
