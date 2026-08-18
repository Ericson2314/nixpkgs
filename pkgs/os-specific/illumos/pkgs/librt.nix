{
  buildPackages,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,
  ld,

  crt,
  headers,
  libcMinimal,
}:

# librt.so.1 -- the POSIX realtime library (`clock_gettime`, `sem_*`, `shm_*`,
# `mq_*`, `timer_*`, `aio_*`).
#
# On illumos every one of those symbols actually lives in libc.so.1; librt is a
# *filter* library (`DYNFLAGS += -F libc.so.1`, see usr/src/lib/librt/Makefile.com)
# whose only content is a mapfile. It has no sources -- `Makefile.filter.com`
# reduces the link to `$(LD) $(MAPFILECLASS) -o $@ $(GSHARED) $(DYNFLAGS)`.
#
# It is packaged because portable software still links `-lrt` unconditionally on
# anything that is not Linux/glibc-2.17+ or Darwin. Without it the link fails
# with "cannot find -lrt" even though the symbols are all present in libc --
# zstd and libarchive both hit this.
mkDerivation {
  libcMinimal = true;
  path = "usr/src/lib/librt/amd64";
  pname = "librt-illumos";

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
    "usr/src/lib/librt"

    "usr/src/common/mapfiles"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    install
    cw
    ld
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

  makeFlags = [
    "MCS=:"
    "POST_PROCESS_O=:"
    "POST_PROCESS_SO=:"
    "LDFLAGS.native="
    "CPPFLAGS.first=-I${headers}/include"
    "LD=${buildPackages.writeShellScript "illumos-ld" ''
      unset SGS_SUPPORT SGS_SUPPORT_32 SGS_SUPPORT_64
      exec ${buildPackages.illumos.ld}/bin/ld "$@"
    ''}"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp librt.so.1 "$out/lib/"
    ln -s librt.so.1 "$out/lib/librt.so"

    runHook postInstall
  '';
}
