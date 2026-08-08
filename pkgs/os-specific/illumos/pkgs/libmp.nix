{
  buildPackages,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,
  ld-native,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# libmp.so.2 -- the ancient SVR4 multiple-precision integer library (`mp_itom`,
# `mp_mult`, `mp_pow`, ...). Nothing modern wants it directly; it is packaged
# because libnsl's Secure RPC key generation (`lib/libnsl/key/gen_dhkeys.c`)
# calls into it, so `-lmp` is a hard prerequisite of a complete libnsl.
mkDerivation {
  libcMinimal = true;
  path = "usr/src/lib/libmp/amd64";
  pname = "libmp-illumos";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libmp"

    "usr/src/common/mapfiles"
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
    "MACH=i386"
    "MACH64=amd64"
    "LD=${
      buildPackages.writeShellScript "illumos-ld" ''
        unset SGS_SUPPORT SGS_SUPPORT_32 SGS_SUPPORT_64
        exec ${buildPackages.illumos.ld-native}/bin/ld "$@"
      ''
    }"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libmp.so.2 "$out/lib/"
    ln -s libmp.so.2 "$out/lib/libmp.so"

    runHook postInstall
  '';
}
