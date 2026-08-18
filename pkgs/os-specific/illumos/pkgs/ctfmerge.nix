{
  lib,
  stdenv,
  mkDerivation,

  compat,
  elfutils,
  libctf,
}:

# ctfmerge(1): merge per-object CTF containers into one and write the result
# back into the linked object. The other half of the CTF pipeline; see
# ctfconvert.nix, which this mirrors.
#
# Built from the gate's own source, `usr/src/cmd/ctfmerge/ctfmerge.c`, and
# not through `usr/src/tools/ctf/ctfmerge` -- which holds no source, only a
# `%.o: $(SRC)/cmd/ctfmerge/%.c` rule and a makefile saying "build this one
# for the machine doing the build". See the standing order in ../default.nix.
#
# Like every other package here, this builds for ITS OWN host platform: plain
# `stdenv`, `$CC`, `NIX_LDFLAGS`. There is no `depsBuildBuild`, no
# `$CC_FOR_BUILD` and no `NIX_LDFLAGS_FOR_BUILD`, because those are for helper
# programs a build runs and discards -- never for the thing being installed.
#
# The reason that is enough: `buildPackages.illumos.ctfmerge` is already an
# instance whose `stdenv` targets the build machine, so in that instance `$CC`
# *is* the host compiler. Consumers reach it by putting `ctfmerge` in
# `nativeBuildInputs`, and splicing picks the build-host instance for them --
# see uts-common.nix and libcMinimal.nix, which already do exactly that and
# needed no change. (Splicing is the usual route, not the only one: a consumer
# that would tie a knot through the scope has to name
# `buildPackages.illumos.<tool>` outright, as ld.nix does for `ONBLD_TOOLS`.)
#
# Reproducing that selection inside this file, with `noCC` plus
# `depsBuildBuild`, is the same mistake as `Makefile.ctf.native`: doing by hand
# what the package set already does.
mkDerivation {
  pname = "ctfmerge";
  path = "usr/src/cmd/ctfmerge";

  extraPaths = [
    # <libctf.h> and, through it, <sys/ctf_api.h> and <sys/ctf.h>. illumos does
    # not ship these, so no host has a copy.
    "usr/src/lib/libctf/common"
    "usr/src/uts/common/sys"
    "usr/src/head"
  ];

  buildInputs = [
    libctf
    elfutils
  ];

  # libctf installs its shared object into `lib/$(MACH)` rather than `lib/`, so
  # cc-wrapper's `-L${libctf}/lib` from `buildInputs` does not find it. That is
  # a wart in libctf.nix -- its build-host form is still built out of
  # `tools/ctf/libctf`, which uses the onbld layout -- not something this
  # package can fix, so name the directory explicitly.
  env.NIX_LDFLAGS = toString [
    "-L${libctf}/lib/i386"
    "-rpath"
    "${libctf}/lib/i386"
  ];

  # One translation unit and one link. The gate's `cmd/ctfmerge/Makefile` is
  # not run: it is `include ../Makefile.cmd`, i.e. a 32-bit build linked by
  # illumos ld with mapfiles, none of which applies to a program being built
  # for a foreign host. Invoking the compiler directly is the whole of what it
  # would have amounted to.
  #
  # Include-path shape, which is load-bearing:
  #
  #  o `-D_LARGEFILE64_SOURCE` first: <sys/ctf_api.h> declares `off64_t`
  #    fields, and glibc only defines that type under this feature-test macro.
  #
  #  o `compat.hostElfCflags` ahead of `compat.stagedCflags`, so <sys/elf.h>
  #    forwards to the host's <elf.h> rather than resolving to illumos' own.
  #    libelf.h has already defined those types by the time <sys/ctf_api.h>
  #    asks for them; see compat/host-elf/sys/elf.h.
  #
  #  o `compat.stagedCflags` for the rest -- the host's libc wins, with
  #    illumos' "_t" integer spellings and `boolean_t` layered on top.
  #
  #  o `-idirafter` for `uts/common` and `head`: both hold headers illumos does
  #    not ship (<sys/ctf_api.h>, <sys/debug.h>) *and* headers every libc has
  #    (<sys/types.h>). Searched after the host's own directories, the host
  #    wins wherever it has an opinion and illumos supplies the rest.
  #
  # ctfmerge needs no libc gap-filler of its own -- it uses only pthreads, mmap
  # and libctf -- but is still linked against `compat` for the shared
  # `_sysconf`/`___errno` shims, which cost nothing unreferenced. compat_host.c
  # is compiled separately because it is by construction a host-headers
  # translation unit, needing the `stat64`/`statvfs64` spellings those two
  # macros unlock; mkfs-ufs.nix compiles it the same way.
  buildPhase = ''
    runHook preBuild

    $CC -c -o compat_host.o -D_GNU_SOURCE -D_LARGEFILE64_SOURCE \
      -I${compat.srcDir} "${compat.hostSource}"

    $CC -o ctfmerge \
      -D_LARGEFILE64_SOURCE \
      ${compat.hostElfCflags} ${compat.stagedCflags} \
      -I "$SRC/lib/libctf/common" \
      -idirafter "$SRC/uts/common" \
      -idirafter "$SRC/head" \
      ctfmerge.c compat_host.o \
      -lctf -lelf -lpthread

    runHook postBuild
  '';

  # `install` on $PATH here is illumos' install(1), whose options are not GNU
  # coreutils'.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp ctfmerge $out/bin/ctfmerge

    runHook postInstall
  '';

  meta = {
    platforms = lib.platforms.unix;
    mainProgram = "ctfmerge";

    # Only the foreign-libc build is written. An illumos host needs none of
    # `compat` and wants `sgs-libelf` rather than elfutils, and nothing here
    # consumes a ctfmerge that runs on illumos -- every user takes the
    # build-host instance through `nativeBuildInputs`. Rather than invent an
    # untested second arm, say so: the previous version of this file guessed at
    # one, and an earlier version silently answered
    # `pkgsCross.x86_64-illumos.illumos.ctfmerge` with a Linux binary.
    broken = stdenv.hostPlatform.isSunOS;
  };
}
