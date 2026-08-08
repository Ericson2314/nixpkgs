{
  mkDerivation,

  illumosSetupHook,
  make,
  install,
}:

# libmd ships <md5.h>, <sha1.h>, <sha2.h> and friends, which libc's
# port/rt/pos4obj.c and others include. Only the headers are wanted here, not
# the library.
mkDerivation {
  name = "libmd-headers";
  path = "usr/src/lib/libmd";
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

  headersOnly = true;

  # install(1) will not create the destination directory itself.
  installPhase = ''
    mkdir -p "$out/include"
    includesPhase
  '';
}
