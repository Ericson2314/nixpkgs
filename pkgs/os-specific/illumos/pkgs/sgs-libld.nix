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
let
  forIllumos = stdenv.hostPlatform.isIllumos;
in

mkDerivation {
  libcMinimal = forIllumos;
  path = if forIllumos then "usr/src/cmd/sgs/libld/amd64" else "usr/src/tools/sgs/libld";

  # Its makefiles index source, object or install directories by $(MACH) /
  # $(MACH64), so it needs the illumos spelling of the CPU. Not the default:
  # setting MACH for a package whose install rules do not expect it relocates
  # that package's output. See `machMakeFlags` in mkDerivation.nix.
  illumosMach = true;
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
    "SGSMSG=${buildPackages.illumos.sgsmsg}/bin/sgsmsg"
    "CONVLIBDIR=-L${sgs-libconv}/lib"
    "CONVLIBDIR64=-L${sgs-libconv}/lib"
    "ELFLIBDIR=-L${sgs-libelf}/lib"
    "ELFLIBDIR64=-L${sgs-libelf}/lib"
    "LDDBGLIBDIR=-L${sgs-liblddbg}/lib"
    "LDDBGLIBDIR64=-L${sgs-liblddbg}/lib"
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

  # See sgs-libelf.nix.
  preBuild = lib.optionalString forIllumos ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) \$(PICS) \$(EXTPICS) -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libld.so.4 "$out/lib/"
    ln -s libld.so.4 "$out/lib/libld.so"

    runHook postInstall
  '';

  meta = {
    platforms = lib.platforms.unix;
  };
}
