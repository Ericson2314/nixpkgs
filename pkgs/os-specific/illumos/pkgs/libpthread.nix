{
  buildPackages,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,
  ld-native,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# libpthread.so.1. On illumos this is a pure *filter* library on libc
# (`DYNFLAGS += -F libc.so.1`, lib/libpthread/Makefile.com:30) -- it has no code
# of its own, since the threads implementation lives in libc.so.1. It exists so
# that `-lpthread` resolves, which plenty of software (gcc's libsanitizer, for
# one) passes unconditionally.
#
# NetBSD's libc join carries libpthread for the same reason; FreeBSD's carries
# libthr.
mkDerivation {
  libcMinimal = true;
  path = "usr/src/lib/libpthread/amd64";
  pname = "libpthread-illumos";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/Makefile.filter.com"
    "usr/src/lib/Makefile.filter.targ"
    "usr/src/lib/libpthread"

    "usr/src/common/mapfiles"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    install
    cw
    ld-native
    (buildPackages.writeShellScriptBin "arch" "echo i386")
    (buildPackages.writeShellScriptBin "mach" "echo i386")
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # No BUILD.SO override here, unlike libm: lib/Makefile.filter.targ:31 already
  # defines the right one for filter libraries --
  #
  #     BUILD.SO = $(LD) $(MAPFILECLASS) -o $@ $(GSHARED) $(DYNFLAGS)
  #
  # which both calls $(LD) directly and passes $(MAPFILECLASS) (= -64, from
  # Makefile.master.64:64). That flag is essential: a filter is built purely
  # from a mapfile with no input objects, so without it ld has nothing to infer
  # the ELF class from and silently emits a 32-bit i386 object, which the
  # linker then rejects as "skipping incompatible".

  makeFlags = [
    "MCS=:"
    "POST_PROCESS_O=:"
    "POST_PROCESS_SO=:"
    "LDFLAGS.native="
    "CPPFLAGS.first=-I${headers}/include"
    "MACH=i386"
    "MACH64=amd64"
    "LD=${
      buildPackages.writeShellScript "illumos-ld" ''
        unset SGS_SUPPORT SGS_SUPPORT_32 SGS_SUPPORT_64
        exec ${buildPackages.illumos.ld-native}/bin/ld "$@"
      ''
    }"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libpthread.so.1 "$out/lib/"
    ln -s libpthread.so.1 "$out/lib/libpthread.so"

    runHook postInstall
  '';
}
