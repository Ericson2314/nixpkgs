{
  lib,
  stdenv,
  mkDerivation,

  cw,
  ld,
  sgs-support,
}:

# mcs(1) -- illumos' own object-file editor, and the program that `strip(1)` is
# a hard link to. `strip -x` is `mcs -d` with the symbol table kept, which is
# exactly what usr/src/Makefile.master's $(STRIP_STABS) runs over every kernel
# module.
#
# Why this matters: GNU objcopy cannot strip an illumos kernel module. It
# rebuilds `.strtab` and drops the DT_NEEDED module-dependency names with it
# (drv/ip: 0x12bd5 -> 0x12b7a, all eight names gone), it zeroes `.dynamic`'s
# sh_link -- which is how krtld finds that table (uts/common/krtld/kobj.c) --
# and on `unix` it reorders the allocatable sections so the multiboot header
# leaves the first 8K and nothing will boot the result. mcs rewrites the file
# the way illumos' own libelf lays it out, and none of that happens.
#
# Built from `usr/src/cmd/sgs/mcs/amd64` through the gate's own makefiles under
# dmake, like every other package here, and for ITS OWN host platform with
# plain `stdenv`. `buildPackages.illumos.mcs` -- the instance whose `stdenv`
# targets the build machine -- is what the cross build consumes, and splicing
# picks it out of `nativeBuildInputs` without this file having to arrange
# anything.
#
# This file previously did the opposite of all of that, and the two halves went
# together: reaching for `$CC_FOR_BUILD` because a build-platform instance
# looked unavailable makes the gate makefile unusable, and once it is unusable
# everything it would have done has to be restated by hand. What that cost was
# a hand-copied list of headers to stage (which is `tools/sgs/include`'s
# ROOTHDRS/SYSHDRS, transcribed), a hand-listed set of translation units (which
# is Makefile.com's $(OBJS)), and a C file written at build time to stub
# `conv_check_native()` so that libconv need not be built. None of it was
# necessary.
#
# What the makefile needs that a foreign host cannot supply, `sgs-support`
# provides -- the staged ELF headers, the NATIVE_BUILD shims and a real
# libconv. `CONVLIBDIR64` and `ELFLIBDIR64` are upstream's own knobs for saying
# where those live.
mkDerivation {
  pname = "mcs";
  path = "usr/src/cmd/sgs/mcs/amd64";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    "usr/src/cmd/sgs/mcs"
    "usr/src/cmd/sgs/Makefile.com"
    "usr/src/cmd/sgs/Makefile.sub"
    "usr/src/cmd/sgs/common"
    "usr/src/cmd/sgs/include"
    "usr/src/cmd/sgs/messages"

    "usr/src/common/elfcap"

    "usr/src/head"
    "usr/src/uts/common/sys"
  ];

  # The shared build-host overlay -- SAVEARGS (without which host gcc dies on
  # `-msave-args`), the Solaris-ld flags GNU ld rejects, the mapfile macros,
  # STACKPROTECT and the post-processing no-ops. Stated once in
  # mkDerivation.nix; restating it per package is exactly how the hand-written
  # buildPhase this replaces came about.

  extraNativeBuildInputs = [ cw ];

  makeFlags = [
    # illumos' MACH/MACH64 are not uname strings; on x86 they are i386/amd64,
    # and the makefiles index directories with them.
    "MACH=i386"
    "MACH64=amd64"

    # Where `-lconv` and `-lelf` live. Upstream points these at the sibling
    # build directories of a full sgs build; here libconv comes from
    # `sgs-support` and illumos' libelf from the native link-editor, which
    # builds and installs one because it needs it too. It has to be illumos'
    # libelf and not elfutils: the layout behaviour that makes this tool safe
    # on a kernel module is libelf's, not mcs'.
    "CONVLIBDIR64=${sgs-support.ldflags}"
    "ELFLIBDIR64=-L${ld}/lib/i386/64"

    # The compile profile an sgs program needs against a foreign libc.
    #
    # This restates cmd/sgs/Makefile.com's own CPPFLAGS line, which is normally
    # exactly the kind of duplication to avoid. It is forced: the shared overlay
    # passes `CPPFLAGS=-D_TS_ERRNO` as a *command-line* macro, and those outrank
    # every makefile assignment -- including Makefile.com line 62, which
    # reassigns CPPFLAGS specifically to put `-I.` and `-I../common` ahead of
    # the parent's. So the sgs include paths vanish and <conv.h> is not found.
    #
    # (Upstream sets this in tools/Makefile.tools as an ordinary assignment, and
    # Makefile.master keeps it in `CPPFLAGS.master`. Emitting it as
    # `CPPFLAGS.master=` instead of `CPPFLAGS=` would make this override
    # unnecessary and fix every cmd/sgs consumer of the overlay at once.)
    "CPPFLAGS=-D_TS_ERRNO -I. -I../common -I$(SGSHOME)/include -I$(SGSHOME)/include/$(MACH) -I$(ELFCAP) ${sgs-support.cflags}"

    # `$(LLDFLAGS64)` is `-R$$ORIGIN/...`, illumos ld's spelling of -rpath, and
    # points into a proto area that does not exist here. The runpath this
    # binary actually needs is set through NIX_LDFLAGS below.
    "LLDFLAGS64="
  ];

  # illumos' libelf is a shared object, so the runpath has to name it.
  env.NIX_LDFLAGS = "-rpath ${ld}/lib/i386/64";

  buildFlags = [ "all" ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp mcs $out/bin/mcs
    # mcs decides what to do from argv[0]; `strip` is a link to it, not a
    # separate program (cmd/sgs/mcs/Makefile.com's $(ROOTLINKS)).
    ln -s mcs $out/bin/strip

    runHook postInstall
  '';

  meta = {
    platforms = lib.platforms.unix;
    mainProgram = "mcs";

    # Only the foreign-libc build is exercised; on an illumos host the headers
    # and libconv come from the system and the packaged sgs-libconv instead,
    # and nothing here consumes an mcs that runs on illumos.
    broken = stdenv.hostPlatform.isSunOS;
  };
}
