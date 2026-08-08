{
  lib,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,

  buildPackages,
}:

# The libdwarf that the CTF tools link against, built as a *native* library for
# the build host.
#
# This is illumos' vendored copy of David Anderson's libdwarf (20200612), not
# the one in nixpkgs: `ctfconvert` consumes the pre-0.x API (`dwarf_elf_init()`
# and friends), which the modern releases no longer provide.
#
# Everything here is a build-host program, so nothing depends on the illumos
# cross toolchain -- hence `noCC`, plus the host compiler by way of
# `depsBuildBuild`. illumos' makefiles find it through `$CC_FOR_BUILD`; see
# `NATIVE_PRIMARY_CC_PATH` in usr/src/Makefile.master.
mkDerivation {
  pname = "libdwarf";
  noCC = true;

  # The i386 directory is entered directly rather than through
  # ../Makefile's `SUBDIRS = $(MACH)` recursion, which does not forward
  # $ROOTONBLD to the sub-make. Despite the name the build is 64-bit; see the
  # comment in tools/ctf/Makefile.ctf.native.
  path = "usr/src/tools/ctf/dwarf/i386";
  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"

    # The whole of tools/ctf rather than the individual makefiles: it is a
    # small, self-contained subtree, and naming pieces of it would not work
    # anyway -- Makefile.ctf.native does not exist upstream, it is created by
    # the patch, so filterSource cannot copy it by name.
    "usr/src/tools/ctf"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/Makefile.rootfs"

    "usr/src/lib/libdwarf/common"

    # Reached by the -idirafter in Makefile.ctf.native: the force-included
    # native_compat.h wants <sys/isa_defs.h> and <sys/ccompile.h>, which no
    # foreign libc has.
    "usr/src/uts/common/sys"
    "usr/src/head"
  ];

  makeFlags = [
    "ROOTONBLD=${builtins.placeholder "out"}"
    "MACH=i386"
    "MACH64=amd64"
  ];

  buildFlags = [ "install" ];
  dontInstall = true;

  extraNativeBuildInputs = [
    cw
  ];

  # Build-platform dependencies, not host-platform ones: the library produced
  # here runs on the machine doing the build.
  depsBuildBuild = [
    buildPackages.stdenv.cc
    buildPackages.elfutils
    buildPackages.zlib
  ];

  # The build installs as it goes, so the target directory has to exist before
  # it starts rather than in preInstall.
  preBuild = ''
    mkdir -p $out/lib/i386
  '';

  meta.platforms = lib.platforms.unix;
}
