{
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

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# cmd/sgs/libelf -> libelf.so.1, built for the target. librtld and libld both
# link against it, and ld.so.1 in turn links against those.
mkDerivation {
  libcMinimal = true;
  path = "usr/src/cmd/sgs/libelf/amd64";
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
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    install
    cw
    ld
    # xlate.c and xlate64.c are generated from .m4 sources.
    gnum4
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
    "M4=m4"
    "ONBLD_TOOLS=${buildPackages.illumos.ld}"
    "CONVLIBDIR=-L${sgs-libconv}/lib"
    "CONVLIBDIR64=-L${sgs-libconv}/lib"
    "LD=${ld-wrapper}"
  ];

  # Makefile.lib's default BUILD.SO links through the compiler driver, i.e. GNU
  # ld, which rejects the Solaris flags in DYNFLAGS. Link with illumos ld
  # instead; ld-wrapper splits the -Wl, prefixes DYNFLAGS carries.
  preBuild = ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) \$(PICS) \$(EXTPICS) -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libelf.so.1 "$out/lib/"
    ln -s libelf.so.1 "$out/lib/libelf.so"

    runHook postInstall
  '';
}
