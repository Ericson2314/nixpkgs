{
  lib,
  mkDerivation,

  compatMakeFlags,
  libelf,
  sharedLink,
  zlib,
}:

# The libdwarf that the CTF tools link against.
#
# This is illumos' vendored copy of David Anderson's libdwarf (20200612), not
# the one in nixpkgs: `ctfconvert` consumes the pre-0.x API (`dwarf_elf_init()`
# and friends), which the modern releases no longer provide.
#
# ONE definition, two instances. `illumos.libdwarf` in a cross set is the
# illumos-hosted shared object; `buildPackages.illumos.libdwarf` is the same
# sources built to run on the machine doing the build, which is what
# `ctfconvert`, `ctfmerge` and `ctfstabs` link against. The scope splices, so
# that is all it takes -- see ../default.nix.
#
# This file used to be a `forIllumos ? ... : ...` conditional selecting between
# `usr/src/lib/libdwarf/amd64` and `usr/src/tools/ctf/dwarf/i386`. Those are
# not two libraries: `tools/ctf/dwarf/Makefile.com` has no sources of its own,
# it compiles `$(SRC)/lib/libdwarf/common` with `Makefile.ctf.native` layered
# on top. That makefile is illumos' answer to "build this for the build
# machine", and splicing is ours; keeping both meant maintaining a second,
# drifting expression of the same library. See the standing order in
# ../default.nix.
#
# What `Makefile.ctf.native` supplied is now supplied from the two places it
# belongs. The link-editor half -- the `Z*` options, the `MAPFILE.*` set,
# `SAVEARGS`, the `POST_PROCESS*`/`STRIP_STABS` no-ops -- comes from
# mkDerivation's build-host overlay, which derives it from the platforms. The
# libc half -- `native_compat.h` and the `-idirafter` search order -- comes
# from `compat`, whose "staged" profile is that same header, packaged.
let
  link = sharedLink {
    libs = [
      libelf
      zlib
    ];
  };
in
mkDerivation {
  pname = "libdwarf";

  illumosLib = true;
  libcMinimal = true;

  # Entered directly rather than through ../Makefile's `SUBDIRS = $(MACH)`
  # recursion, which does not forward the macros set here to the sub-make.
  path = "usr/src/lib/libdwarf/amd64";
  extraPaths = [
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libdwarf"
    "usr/src/lib/libdwarf/common"
    "usr/src/common/mapfiles"

    # Reached by the `-idirafter` below on a foreign host: the force-included
    # native_compat.h wants <sys/isa_defs.h> and <sys/ccompile.h>, which no
    # foreign libc has.
    "usr/src/uts/common/sys"
    "usr/src/head"
  ];

  outputs = [
    "out"
    "dev"
  ];

  buildInputs = link.buildInputs;

  env.NIX_CFLAGS_COMPILE = builtins.toString (link.cflags ++ [ "-Wno-error" ]);

  makeFlags = compatMakeFlags { };

  buildFlags = [ "all" ];

  preBuild = link.preBuild;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libdwarf.so.1 "$out/lib/"
    ln -s libdwarf.so.1 "$out/lib/libdwarf.so"

    mkdir -p "$dev/include"
    cp ../common/dwarf.h ../common/libdwarf.h "$dev/include/"

    runHook postInstall
  '';

  meta.platforms = lib.platforms.unix;
}
