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
  #
  # This is the BUILD.SO override the other libraries point at, so the general
  # rule for these lines lives here:
  #
  #   Every `-L` naming a *real* dependency gets a matching `-R`. A `-L` is a
  #   link-time search path and leaves nothing behind in the object, so without
  #   the `-R` there is no DT_RUNPATH -- and, because nix finds references by
  #   scanning the built output for store paths, no reference either. The
  #   library then drops out of the closure and never reaches the boot archive,
  #   so it is not merely unfindable at run time, it is not on the disk. See
  #   `illumos: give every -L in the library links its matching -R`.
  #
  #   Over-supplying `-R` is safe and self-correcting: DYNFLAGS carries
  #   `-zignore`, and the link-editor drops runpath entries it did not end up
  #   needing. libresolv was linked with an `-R` for libmp and came out with a
  #   DT_RUNPATH naming only libsocket, libnsl and libmd -- exactly its real
  #   DT_NEEDEDs. So DT_RUNPATH reflects what was actually used rather than
  #   what was asked for, and the only failure mode to worry about is
  #   *under*-supplying.
  #
  #   libcMinimal and libssp_ns are the deliberate exception and keep a bare
  #   `-L`, as below: they are the bootstrap libc, present only so the link
  #   resolves, and recording a RUNPATH to them would pin the *minimal* libc at
  #   run time in place of the composite -- which is what the composite exists
  #   to avoid.
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
