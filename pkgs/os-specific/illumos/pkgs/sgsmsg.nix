{
  lib,
  mkDerivation,

  cw,
  compat,
}:

# sgsmsg(1ONBLD): the message-catalogue generator every `cmd/sgs` component
# runs on its own `common/*.msg` template to produce `msg.h` and `msg.c`.
# Nothing under `cmd/sgs` compiles without it.
#
# `usr/src/tools` rather than `usr/src/cmd` is one of the documented exemptions
# in ../default.nix: `usr/src/cmd/sgs/include/sgsmsg.h` is the header alone --
# the program exists nowhere else in the gate.
#
# Split out of the `usr/src/tools/sgs` aggregate that `ld` used to build. That
# aggregate was the only source of sgsmsg, so every sgs library had to name
# `buildPackages.illumos.ld` as its `ONBLD_TOOLS`; a library that `ld` itself
# links then closed a cycle. One small package instead, which is all any of
# them ever wanted from it.
mkDerivation {
  pname = "sgsmsg";

  path = "usr/src/tools/sgs/sgsmsg";
  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"
    "usr/src/tools/sgs/Makefile.com"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.targ"
    "usr/src/cmd/sgs/Makefile.com"
    "usr/src/cmd/sgs/common"
    "usr/src/cmd/sgs/include"

    "usr/src/common/avl"

    "usr/src/uts/common/sys"
    "usr/src/head"
  ];

  makeFlags = [
    "ROOTONBLD=${builtins.placeholder "out"}"

    # tools/Makefile.tools points COMPAT_DIR at usr/src/tools/libcompat/common.
    # `compat` is the nixpkgs package expressing the same thing, and it is what
    # the rest of this set already uses; its `include/` holds native_compat.h
    # under exactly the name COMPAT_CPPFLAGS force-includes.
    "COMPAT_DIR=${compat}/include"
  ];

  # avl.c wants illumos <sys/debug.h>, which glibc has no counterpart for.
  # `-idirafter` so the host still wins for everything it does have; $SRC is
  # only known at build time, so this cannot be an `env` attribute.
#
# The mkdir is here rather than in preInstall because the build installs as it
# goes, so the target directories have to exist before it starts.
  preBuild = ''
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -idirafter $SRC/uts/common -idirafter $SRC/head"
    mkdir -p $out/bin/i386 $out/man/man1onbld
  '';

  buildFlags = [ "install" ];
  dontInstall = true;

  extraNativeBuildInputs = [ cw ];

  # `$(SGSMSG)` is $(ONBLD_TOOLS)/bin/$(MACH)/sgsmsg, so a consumer only has to
  # say `ONBLD_TOOLS=${...}`. No symlink is needed for the plain name: the
  # gate installs both $(ROOTONBLDMACHPROG) and $(ROOTONBLDPROG), so
  # `bin/sgsmsg` already exists and `ln -s` onto it fails.

  meta.platforms = lib.platforms.unix;
}
