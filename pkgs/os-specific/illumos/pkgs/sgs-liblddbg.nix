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
  libcompat,
  sgsmsg,

  ld-wrapper,
  sgs-libconv,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# cmd/sgs/liblddbg -> liblddbg.so.4, built for the target. ld.so.1 references
# Dbg_setup() and friends directly (rtld/common/debug.c), lazily loaded, so
# this has to exist at link time even though `-z ignore` keeps it out of the
# final NEEDED list.
let
  forIllumos = stdenv.hostPlatform.isIllumos;
in

mkDerivation {
  libcMinimal = forIllumos;
  path = if forIllumos then "usr/src/cmd/sgs/liblddbg/amd64" else "usr/src/tools/sgs/liblddbg";
  pname = "sgs-liblddbg";

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
    "usr/src/cmd/sgs/liblddbg"
    "usr/src/cmd/sgs/include"
    "usr/src/cmd/sgs/messages"
    # SGSCOMMONOBJ = alist.o, compiled from cmd/sgs/common.
    "usr/src/cmd/sgs/common"

    "usr/src/common/elfcap"
    "usr/src/common/mapfiles"

    "usr/src/lib/libc/inc"
  ]
  ++ lib.optionals (!forIllumos) [
    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"
    "usr/src/tools/sgs/Makefile.com"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    install
    cw
    (buildPackages.writeShellScriptBin "arch" "echo i386")
    (buildPackages.writeShellScriptBin "mach" "echo i386")
  ]
  ++ lib.optionals forIllumos [ ld ];

  buildInputs = lib.optionals forIllumos [
    headers
    crt
    libcMinimal
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString (
    lib.optional forIllumos "-B${crt}/lib" ++ [ "-Wno-error" ]
  );

  buildFlags = [ "all" ];

  makeFlags = [
    "MCS=:"
    "POST_PROCESS_O=:"
    "POST_PROCESS_SO=:"
    "LDFLAGS.native="
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

  # See sgs-libelf.nix: Makefile.lib's default BUILD.SO links through the
  # compiler driver, i.e. GNU ld, which cannot handle these flags or mapfiles.
  preBuild = lib.optionalString forIllumos ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) \$(PICS) \$(EXTPICS) -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp liblddbg.so.4 "$out/lib/"
    ln -s liblddbg.so.4 "$out/lib/liblddbg.so"

    runHook postInstall
  '';

  meta = {
    platforms = lib.platforms.unix;
  };
}
