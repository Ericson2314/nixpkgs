{
  lib,
  mkDerivation,

  compatMakeFlags,
  sharedLink,
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
let
  link = sharedLink { };
in
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

    # Reached by the `-idirafter` that `compatMakeFlags` adds on a foreign
    # host: avl.c includes <sys/debug.h>, which no other libc has.
    "usr/src/uts/common/sys"
    "usr/src/head"
  ];

  makeFlags = compatMakeFlags { };

  buildInputs = link.buildInputs;

  env.NIX_CFLAGS_COMPILE = builtins.toString (link.cflags ++ [ "-Wno-error" ]);

  buildFlags = [ "all" ];

  # The link line comes from the scope: see `sharedLink` in ../default.nix,
  # and libm.nix for why `BUILD.SO` has to call `$(LD)` directly at all. On a
  # build-host instance it is empty -- GNU ld needs none of it.
  preBuild = link.preBuild;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libavl.so.1 "$out/lib/"
    ln -s libavl.so.1 "$out/lib/libavl.so"

    runHook postInstall
  '';

  # Both instances are real: the CTF tools link the build-host one.
  meta.platforms = lib.platforms.unix;
}
