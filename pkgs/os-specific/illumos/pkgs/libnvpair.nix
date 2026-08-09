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
  libnsl,
  # libnsl.so.1 pulls in libmp/libmd, and the illumos link-editor insists on
  # finding a shared object's own dependencies on the link path.
  libmd,
  libmp,
}:

# libnvpair.so.1 -- illumos' name/value pair lists. The bulk of the
# implementation is shared with the kernel and lives in `usr/src/common/nvpair`;
# `usr/src/lib/libnvpair` adds the userland printing/JSON wrappers.
#
# libcMinimal.nix already pulls this directory in for its *headers*
# (`-I$SRC/lib/libnvpair`); this package is what actually builds the shared
# object, which `coreutils` needs (`ld: cannot find -lnvpair`, via the
# illumos-specific bits of gnulib/`sys/nvpair.h` users).
mkDerivation {
  libcMinimal = true;
  path = "usr/src/lib/libnvpair/amd64";
  pname = "libnvpair-illumos";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libnvpair"

    # nvpair.c / fnvpair.c / nvpair_alloc_fixed.c are compiled straight out of
    # the code shared with the kernel.
    "usr/src/common/nvpair"

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

  # `-lnsl` in `Makefile.com`'s LDLIBS is not vestigial, despite the "libraries
  # added to the next line must be present in miniroot" comment above it:
  # `common/nvpair/nvpair.c` serialises with XDR, so `xdr_int`, `xdr_string`,
  # `xdrmem_create` and friends are genuine undefined symbols and `-zdefs`
  # rejects the link without libnsl. (This was checked by trying to drop it.)
  #
  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly.
  preBuild = ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) \$(PICS) \$(EXTPICS) -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libnsl}/lib -L${libmd}/lib -L${libmp}/lib \$(LDLIBS)")
  '';

  makeFlags = [
    "MCS=:"
    "POST_PROCESS_O=:"
    "POST_PROCESS_SO=:"
    "LDFLAGS.native="
    "CPPFLAGS.first=-I${headers}/include"
    "MACH=i386"
    "MACH64=amd64"
    "LD=${
      buildPackages.writeShellScript "illumos-ld" ''
        unset SGS_SUPPORT SGS_SUPPORT_32 SGS_SUPPORT_64
        exec ${buildPackages.illumos.ld}/bin/ld "$@"
      ''
    }"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libnvpair.so.1 "$out/lib/"
    ln -s libnvpair.so.1 "$out/lib/libnvpair.so"

    mkdir -p "$dev/include"
    cp ../libnvpair.h "$dev/include/"

    runHook postInstall
  '';
}
