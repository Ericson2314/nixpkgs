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

  ld-wrapper,
  sgs-libconv,
  sgs-libelf,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# cmd/sgs/librtld -> librtld.so.1, built for the target. ld.so.1 references its
# symbols for dldump(3C) and is linked against it.
mkDerivation {
  libcMinimal = true;
  path = "usr/src/cmd/sgs/librtld/amd64";

  # Its makefiles index source, object or install directories by $(MACH) /
  # $(MACH64), so it needs the illumos spelling of the CPU. Not the default:
  # setting MACH for a package whose install rules do not expect it relocates
  # that package's output. See `machMakeFlags` in mkDerivation.nix.
  illumosMach = true;
  pname = "sgs-librtld";

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
    "usr/src/cmd/sgs/librtld"
    "usr/src/cmd/sgs/include"
    "usr/src/cmd/sgs/messages"
    # Makefile.com adds -I../../rtld/common for _rtld.h and friends.
    "usr/src/cmd/sgs/rtld/common"

    "usr/src/common/elfcap"
    "usr/src/common/sgsrtcid"
    "usr/src/common/mapfiles"

    "usr/src/uts/common/krtld"
    "usr/src/uts/intel/amd64/krtld"

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

  buildInputs = lib.optionals stdenv.hostPlatform.isIllumos [
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
    # $(SGSMSG) is $(ONBLD_TOOLS)/bin/$(MACH)/sgsmsg. `ld` used to build and
    # install sgsmsg as a by-product of the `tools/sgs` aggregate, but it is
    # built from `cmd/sgs/ld` now and no longer ships it, so name the `sgsmsg`
    # package directly. `buildPackages.illumos.` because sgsmsg runs during
    # this build; the target instance would need libc and recurse.
    "SGSMSG=${buildPackages.illumos.sgsmsg}/bin/sgsmsg"
    "CONVLIBDIR=-L${sgs-libconv}/lib"
    "CONVLIBDIR64=-L${sgs-libconv}/lib"
    "ELFLIBDIR=-L${sgs-libelf}/lib"
    "ELFLIBDIR64=-L${sgs-libelf}/lib"
    "LD=${ld-wrapper}"
  ];

  # See sgs-libelf.nix.
  preBuild = ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) \$(PICS) \$(EXTPICS) -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp librtld.so.1 "$out/lib/"
    ln -s librtld.so.1 "$out/lib/librtld.so"

    runHook postInstall
  '';

  meta = {
    platforms = lib.platforms.unix;
  };
}
