{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# libm.so.2. Unlike libc's amd64 makefile, lib/libm/Makefile.com already sets
# `LIBS = $(DYNLIB)`, so the shared library is built without further prompting.
# It links against -lc, hence the libcMinimal stdenv.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libm/amd64";
  pname = "libm-illumos";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    # libm/Makefile.com:500 includes it.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libm"

    # DYNFLAGS pulls in the shared link-editor mapfiles (map.pagealign,
    # map.noexdata) from common/mapfiles.
    "usr/src/common/mapfiles"
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

  # See libcMinimal.nix for why each of these is needed; the reasoning is
  # identical here.
  buildFlags = [ "all" ];

  # lib/libc/amd64/Makefile overrides BUILD.SO to invoke $(LD) directly, but
  # libm uses Makefile.lib's default, which goes through the compiler driver --
  # so the link runs GNU ld via collect2 and dies on -Bdirect. Point it at the
  # same illumos ld. This has to go through makeFlagsArray rather than
  # makeFlags because the value contains spaces.
  preBuild = ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) \$(PICS) \$(EXTPICS) -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libm.so.2 "$out/lib/"
    ln -s libm.so.2 "$out/lib/libm.so"

    mkdir -p "$dev"

    runHook postInstall
  '';
}
