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
    "ONBLD_TOOLS=${buildPackages.illumos.ld}"
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
}
