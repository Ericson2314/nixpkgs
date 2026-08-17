{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# libavl.so.1 -- the AVL tree implementation shared with the kernel. The whole
# library is one object, compiled straight out of `usr/src/common/avl`; the
# `usr/src/lib/libavl` directory contains nothing but a Makefile and a
# mapfile.
#
# Nothing in nixpkgs asks for `-lavl` directly. It is here because
# `libsec.so.1` and `libidmap.so.1` both carry it as a `DT_NEEDED`, and the
# illumos link-editor insists on finding a shared object's own dependencies on
# the link path before it will let a consumer link against it.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libavl/amd64";
  pname = "libavl";

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libavl"

    # OBJECTS is built from $(SRC)/common/avl via Makefile.com's own
    # `pics/%.o: $(COMDIR)/%.c` rule.
    "usr/src/common/avl"

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

  buildFlags = [ "all" ];

  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture.
  preBuild = ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libavl.so.1 "$out/lib/"
    ln -s libavl.so.1 "$out/lib/libavl.so"

    runHook postInstall
  '';
}
