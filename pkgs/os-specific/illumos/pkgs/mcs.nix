{
  lib,
  stdenv,
  buildPackages,
  mkDerivation,

  compat,
  ld,
}:

# mcs(1) -- illumos' own object-file editor, and the program that `strip(1)`
# is a hard link to. `strip -x` is `mcs -d` with the symbol table kept, which
# is exactly what usr/src/Makefile.master's $(STRIP_STABS) runs over every
# kernel module.
#
# Why this matters: GNU objcopy cannot strip an illumos kernel module. It
# rebuilds `.strtab` and drops the DT_NEEDED module-dependency names with it
# (drv/ip: 0x12bd5 -> 0x12b7a, all eight names gone), it zeroes `.dynamic`'s
# sh_link -- which is how krtld finds that table (uts/common/krtld/kobj.c) --
# and on `unix` it reorders the allocatable sections so the multiboot header
# leaves the first 8K and nothing will boot the result. mcs rewrites the file
# the way illumos' own libelf lays it out, and none of that happens.
#
# There is *one* attribute, and which platform it is built for comes from the
# package set, not from the name -- the same arrangement as ld.nix.
# `buildPackages.illumos.mcs` is the build-host binary the cross build wants;
# `illumos.mcs` in a cross set is the mcs(1) that ships.
#
#  o For an illumos host: usr/src/cmd/sgs/mcs/amd64, through the gate's own
#    makefiles, linked against the packaged sgs-libconv/sgs-libelf.
#
#  o For the build host: the same six sources, compiled directly. This is the
#    one place where the gate makefiles are *not* used, and deliberately so.
#    illumos' answer to "run an sgs program on the build machine" is
#    usr/src/tools/sgs -- a second copy of the makefiles built -DNATIVE_BUILD
#    -- and it has no `mcs` subdirectory. Rather than add one (a third source
#    of truth for a program that is six .c files, one library and no generated
#    message catalogue), the recipe is stated here. What it needs from the
#    NATIVE_BUILD arrangement is only two things, both already packaged:
#    `compat`'s staged-header profile, and illumos' libelf -- which
#    `buildPackages.illumos.ld` already builds and installs, because the
#    native link-editor needs it too.
let
  forIllumos = stdenv.hostPlatform.isSunOS;

  commonPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/cmd/sgs/common"
    "usr/src/cmd/sgs/include"

    "usr/src/common/elfcap"

    "usr/src/head"
    "usr/src/uts/common/sys"
  ];

  # The build-host recipe.
  #
  # `noCC`, with the host compiler arriving through depsBuildBuild, is the
  # shape every other build-host tool here has (see pkgs/elfextract.nix).
  native = {
    noCC = true;

    path = "usr/src/cmd/sgs/mcs";
    extraPaths = commonPaths;

    depsBuildBuild = [ buildPackages.stdenv.cc ];

    # ELF headers that `compat` does not stage. Deliberately staged here rather
    # than added to `compat`: `compat` is an input of elfextract, which is an
    # input of `unix`, so growing its list rebuilds the kernel.
    #
    # <sys/secflags.h> and <sys/procset.h> are not ELF headers; they are pulled
    # in by cmd/sgs/include/conv.h's chain and glibc has no counterpart.
    headHeaders = [
      "gelf.h"
      "libelf.h"
      "nlist.h"
      "elf.h"
    ];
    sysHeaders = [
      "machelf.h"
      "link.h"
      "avl.h"
      "avl_impl.h"
      "debug.h"
      "secflags.h"
      "sysmacros.h"
      "procset.h"
    ];

    buildPhase = ''
      runHook preBuild

      mkdir -p staged/sys obj
      for h in "''${headHeaders[@]}"; do cp "$SRC/head/$h" staged/; done
      for h in "''${sysHeaders[@]}"; do cp "$SRC/uts/common/sys/$h" staged/sys/; done

      # conv_check_native() is the only thing mcs takes from libconv, and on
      # LP64 upstream's definition (cmd/sgs/libconv/common/arch.c) is exactly
      # this: the 32-bit build re-execs its 64-bit counterpart, the 64-bit one
      # does nothing. Restating it is cheaper than building libconv here, which
      # would need sgsmsg and a generated message catalogue for one stub.
      printf '%s\n' \
        '#include <libelf.h>' \
        'unsigned char' \
        'conv_check_native(char **argv, char **envp)' \
        '{' \
        '	return (ELFCLASS64);' \
        '}' > obj/conv_check_native.c

      # -include libintl.h: the sources call gettext() without including it,
      # relying on illumos' <string.h> chain to have pulled it in.
      cflags="-DNATIVE_BUILD -O2 -w
        -Istaged ${compat.stagedCflags}
        -include libintl.h
        -I$SRC/cmd/sgs/mcs/common
        -I$SRC/cmd/sgs/include -I$SRC/cmd/sgs/include/i386
        -I$SRC/cmd/sgs/common
        -I$SRC/common/elfcap"

      for f in main file utils global message; do
        $CC_FOR_BUILD -c -o "obj/$f.o" $cflags "$SRC/cmd/sgs/mcs/common/$f.c"
      done
      $CC_FOR_BUILD -c -o obj/alist.o $cflags "$SRC/cmd/sgs/common/alist.c"
      $CC_FOR_BUILD -c -o obj/conv_check_native.o $cflags obj/conv_check_native.c

      # illumos' libelf, not the host's: the layout behaviour that makes this
      # tool safe on a kernel module is libelf's, not mcs'.
      $CC_FOR_BUILD -o obj/mcs obj/*.o \
        -L${ld}/lib/i386/64 -lelf -Wl,-rpath,${ld}/lib/i386/64

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      cp obj/mcs $out/bin/mcs
      # mcs decides what to do from argv[0]; `strip` is a link to it, not a
      # separate program (cmd/sgs/mcs/Makefile.com's $(ROOTLINKS)).
      ln -s mcs $out/bin/strip

      runHook postInstall
    '';
  };

  # The shipping mcs(1). Not exercised by anything yet -- everything here wants
  # `buildPackages.illumos.mcs` -- so this exists to give the attribute the
  # right shape on an illumos host.
  hosted = {
    path = "usr/src/cmd/sgs/mcs/amd64";
    extraPaths = commonPaths ++ [
      "usr/src/lib/Makefile.lib"
      "usr/src/lib/Makefile.lib.64"
      "usr/src/lib/Makefile.targ"
      "usr/src/cmd/Makefile.cmd"
      "usr/src/cmd/Makefile.ctf"
      "usr/src/cmd/Makefile.targ"
      "usr/src/cmd/sgs/Makefile.com"
      "usr/src/cmd/sgs/Makefile.sub"
      "usr/src/cmd/sgs/messages"
    ];
  };
in
mkDerivation (
  {
    pname = "mcs";
  }
  // (if forIllumos then hosted else native)
  // {
    meta = {
      platforms = lib.platforms.unix;
      # See the comment on `hosted` above: unfinished, and nothing consumes it.
      broken = forIllumos;
    };
  }
)
