{
  lib,
  stdenv,
  buildPackages,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,
  ld,
  gnum4,

  ld-wrapper,
  sgs-libconv,

  libcompat,
  sgsmsg,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# cmd/sgs/libelf -> libelf.so.1, built for the target. librtld and libld both
# link against it, and ld.so.1 in turn links against those.
let
  forIllumos = stdenv.hostPlatform.isIllumos;
in

mkDerivation {
  libcMinimal = forIllumos;
  path = if forIllumos then "usr/src/cmd/sgs/libelf/amd64" else "usr/src/tools/sgs/libelf";
  pname = "sgs-libelf";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/Makefile.rootfs"

    "usr/src/cmd/sgs/Makefile.com"
    "usr/src/cmd/sgs/libelf"
    "usr/src/cmd/sgs/include"
    "usr/src/cmd/sgs/messages"

    "usr/src/common/elfcap"

    "usr/src/lib/libc/inc"

    # DYNFLAGS pulls in the shared link-editor mapfiles from common/mapfiles.
    "usr/src/common/mapfiles"
  ]
  ++ lib.optionals (!forIllumos) [
    # tools/sgs/libelf/Makefile includes ../../Makefile.tools and ../Makefile.com.
    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"
    "usr/src/tools/sgs/Makefile.com"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    install
    cw
    # xlate.c and xlate64.c are generated from .m4 sources.
    gnum4
    (buildPackages.writeShellScriptBin "arch" "echo i386")
    (buildPackages.writeShellScriptBin "mach" "echo i386")
  ]
  # Only the illumos arm links with illumos ld; the native one uses the host's.
  # Naming `ld` unconditionally is a cycle -- `ld` links this library.
  ++ lib.optionals forIllumos [ ld ];

  buildInputs = lib.optionals forIllumos [
    headers
    crt
    libcMinimal
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString (lib.optional forIllumos "-B${crt}/lib" ++ [ "-Wno-error" ]);

  buildFlags = [ "all" ];

  makeFlags = [
    "MCS=:"
    "POST_PROCESS_O=:"
    "POST_PROCESS_SO=:"
    "LDFLAGS.native="
    "M4=m4"
    "SGSMSG=${sgsmsg}/bin/sgsmsg"
    "CONVLIBDIR=-L${sgs-libconv}/lib"
    "CONVLIBDIR64=-L${sgs-libconv}/lib"
  ]
  ++ lib.optionals forIllumos [
    "CPPFLAGS.first=-I${headers}/include"
    "LD=${ld-wrapper}"
  ]
  ++ lib.optionals (!forIllumos) [
    "ROOTONBLD=${builtins.placeholder "out"}"
    "COMPAT_DIR=${libcompat}/include-native"
    "COMPAT_INC=${libcompat}/include"
  ];

  # Makefile.lib's default BUILD.SO links through the compiler driver, i.e. GNU
  # ld, which rejects the Solaris flags in DYNFLAGS. Link with illumos ld
  # instead; ld-wrapper splits the -Wl, prefixes DYNFLAGS carries.
  preBuild = lib.optionalString forIllumos ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) \$(PICS) \$(EXTPICS) -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libelf.so.1 "$out/lib/"
    ln -s libelf.so.1 "$out/lib/libelf.so"

    runHook postInstall
  '';

  meta = {
    platforms = lib.platforms.unix;
  };
}
