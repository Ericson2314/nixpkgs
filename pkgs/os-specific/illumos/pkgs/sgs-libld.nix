{
  buildPackages,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,
  ld,

  ld-wrapper,
  sgs-libconv,
  sgs-libelf,
  sgs-liblddbg,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# cmd/sgs/libld -> libld.so.4, built for the target. ld.so.1 links against it
# for `ld.so.1 -e` configuration-file handling (rtld/common/config_elf.c).
mkDerivation {
  libcMinimal = true;
  path = "usr/src/cmd/sgs/libld/amd64";
  pname = "sgs-libld";

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
    "usr/src/cmd/sgs/libld"
    "usr/src/cmd/sgs/include"
    "usr/src/cmd/sgs/messages"
    # SGSCOMMONOBJ: alist.o, assfail.o, findprime.o, string_table.o, strhash.o.
    "usr/src/cmd/sgs/common"

    "usr/src/common/avl"
    "usr/src/common/elfcap"
    "usr/src/common/sgsrtcid"
    "usr/src/common/mapfiles"

    # The relocation engines (doreloc.c) are shared with krtld, and libld
    # compiles every target's copy into every libld.
    "usr/src/uts/common/krtld"
    "usr/src/uts/common/sys"
    "usr/src/uts/intel/ia32/krtld"
    "usr/src/uts/intel/amd64/krtld"
    "usr/src/uts/sparc/krtld"
    "usr/src/uts/sparc/sys"

    "usr/src/lib/libc/inc"
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
    "ONBLD_TOOLS=${buildPackages.illumos.ld}"
    "CONVLIBDIR=-L${sgs-libconv}/lib"
    "CONVLIBDIR64=-L${sgs-libconv}/lib"
    "ELFLIBDIR=-L${sgs-libelf}/lib"
    "ELFLIBDIR64=-L${sgs-libelf}/lib"
    "LDDBGLIBDIR=-L${sgs-liblddbg}/lib"
    "LDDBGLIBDIR64=-L${sgs-liblddbg}/lib"
    "LD=${ld-wrapper}"
  ];

  # See sgs-libelf.nix.
  preBuild = ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) \$(PICS) \$(EXTPICS) -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libld.so.4 "$out/lib/"
    ln -s libld.so.4 "$out/lib/libld.so"

    runHook postInstall
  '';
}
