{
  lib,
  mkDerivation,

  cw,
  compat,
  buildPackages,
}:

# mbh_patch(1ONBLD): fills in the multiboot header's load addresses in a linked
# `unix` (uts/i86pc/unix/Makefile:172).
#
# A build-host program, so `noCC` plus the host compiler via `depsBuildBuild`;
# see pkgs/libdwarf.nix. Like elfextract it needs no libelf, just illumos'
# <sys/elf.h> and <sys/multiboot*.h> from the staged set in pkgs/compat.
mkDerivation {
  pname = "mbh_patch";
  noCC = true;

  path = "usr/src/tools/mbh_patch";
  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"
  ];

  makeFlags = [
    "ROOTONBLD=${builtins.placeholder "out"}"
    "MACH=i386"
    "MACH64=amd64"

    # See elfextract.nix for both of these.
    "NATIVE_MACH=amd64"
    "LDCHECKS="

    # POST_PROCESS ends in $(STRIP_STABS), i.e. `$(STRIP) -x $@`
    # (Makefile.master:979). STRIP is undefined for a `noCC` derivation, so the
    # recipe degenerates to running `-x` as a command. These are build tools,
    # not deliverables, and nothing needs them stripped; tools/sgs/Makefile.com
    # neutralises the same macro.
    "STRIP_STABS=:"

    # Makefile.master:150 spells the installer `install`, which on a Linux
    # build host is coreutils' and does not take -f. illumos' own is
    # install.bin; tools/ctf/Makefile.ctf.native redirects it the same way.
    "INS=install.bin"

    # Drop the `CPPFLAGS += -I../../uts/common` its Makefile adds. Putting the
    # whole kernel sys directory ahead of glibc's headers means illumos'
    # <sys/types.h> and <sys/stat.h> get mixed into glibc's <stdlib.h> chain,
    # and the two disagree about struct stat, int8_t and much else. The staged
    # subset in pkgs/compat is what replaces it.
    "CPPFLAGS=-D_TS_ERRNO"
  ];

  buildFlags = [ "install" ];
  dontInstall = true;

  extraNativeBuildInputs = [ cw ];

  depsBuildBuild = [ buildPackages.stdenv.cc ];

  # The build installs as it goes, so the target directory has to exist before
  # it starts rather than in preInstall.
  preBuild = ''
    mkdir -p $out/bin/i386
    export NIX_CFLAGS_COMPILE_FOR_BUILD="$NIX_CFLAGS_COMPILE_FOR_BUILD ${compat.stagedCflags}"
  '';

  postFixup = ''
    ln -s i386/mbh_patch $out/bin/mbh_patch
  '';

  meta.platforms = lib.platforms.unix;
}
