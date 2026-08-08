{
  buildPackages,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,
  ld-native,

  sgs-ld,
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
mkDerivation {
  libcMinimal = true;
  path = "usr/src/cmd/sgs/liblddbg/amd64";
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

  makeFlags = [
    "MCS=:"
    "POST_PROCESS_O=:"
    "POST_PROCESS_SO=:"
    "LDFLAGS.native="
    "CPPFLAGS.first=-I${headers}/include"
    "MACH=i386"
    "MACH64=amd64"
    "ONBLD_TOOLS=${buildPackages.illumos.ld-native}"
    "CONVLIBDIR=-L${sgs-libconv}/lib"
    "CONVLIBDIR64=-L${sgs-libconv}/lib"
    "LD=${sgs-ld}"
  ];

  # See sgs-libelf.nix: Makefile.lib's default BUILD.SO links through the
  # compiler driver, i.e. GNU ld, which cannot handle these flags or mapfiles.
  preBuild = ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) \$(PICS) \$(EXTPICS) -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp liblddbg.so.4 "$out/lib/"
    ln -s liblddbg.so.4 "$out/lib/liblddbg.so"

    runHook postInstall
  '';
}
