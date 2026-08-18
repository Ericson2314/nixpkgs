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
  libssp_ns,
}:

# libmd.so.1 -- MD4/MD5/SHA1/SHA2/Edon-R/Skein message digests. The algorithm
# code is shared with the kernel and lives in `usr/src/common/crypto`; this
# directory only adds the amd64 assembler variants and the mapfile.
#
# `libmd-headers.nix` already installs the `<md5.h>`/`<sha1.h>`/`<sha2.h>`
# headers for libc's benefit; this package is the actual shared object, needed
# because libnsl's `key/xcrypt.c` calls `MD5Init`/`MD5Update`/`MD5Final`.
mkDerivation {
  libcMinimal = true;
  path = "usr/src/lib/libmd/amd64";

  # Its makefiles index source, object or install directories by $(MACH) /
  # $(MACH64), so it needs the illumos spelling of the CPU. Not the default:
  # setting MACH for a package whose install rules do not expect it relocates
  # that package's output. See `machMakeFlags` in mkDerivation.nix.
  illumosMach = true;
  pname = "libmd-illumos";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libmd"

    # The digest implementations, and the perl generators for the amd64
    # assembler routines, live in the code shared with the kernel.
    "usr/src/common/crypto"

    "usr/src/common/mapfiles"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    install
    cw
    ld
    # amd64/Makefile generates md5_amd64.S and the sha{1,256,512}-x86_64.S from
    # the OpenSSL-derived perl scripts under common/crypto.
    buildPackages.perl
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

  # See libm.nix for why BUILD.SO has to be redefined to call $(LD) directly.
  preBuild = ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) \$(PICS) \$(EXTPICS) -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

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
    cp libmd.so.1 "$out/lib/"
    ln -s libmd.so.1 "$out/lib/libmd.so"

    runHook postInstall
  '';
}
