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

# libmd5.so.1 -- the MD5 message-digest interface, `MD5Init`/`MD5Update`/
# `MD5Final`.
#
# Like librt, this has no code of its own: it is a *filter* library, and its
# filtee is libmd.so.1 rather than libc (`DYNFLAGS += -F libmd.so.1`, see
# usr/src/lib/libmd5/Makefile.com). The whole library is one mapfile, and
# `Makefile.filter.com` reduces the link to
# `$(LD) $(MAPFILECLASS) -o $@ $(GSHARED) $(DYNFLAGS)` -- no objects, no
# LDLIBS. The symbols resolve at run time out of `illumos.libmd`, which is
# already packaged.
#
# It is here because `svc.startd` links `-lmd5`: startd hashes manifest
# contents to decide whether a manifest has changed since it was last
# imported.
mkDerivation {
  libcMinimal = true;
  path = "usr/src/lib/libmd5/amd64";
  pname = "libmd5";

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
    "usr/src/lib/libmd5"

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
    cp libmd5.so.1 "$out/lib/"
    ln -s libmd5.so.1 "$out/lib/libmd5.so"

    runHook postInstall
  '';
}
