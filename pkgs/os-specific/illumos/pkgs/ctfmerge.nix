{
  lib,
  stdenv,
  mkDerivation,

  cw,
  compat,
  elfutils,
  libctf,
}:

# ctfmerge(1): merge per-object CTF containers into one and write the result
# back into the linked object. The other half of the CTF pipeline; see
# ctfconvert.nix, which this mirrors.
#
# Built from `usr/src/cmd/ctfmerge`, through the gate's own makefile, under
# dmake -- like every other package in this set. Not through
# `usr/src/tools/ctf/ctfmerge`, which holds no source: it is a `%.o:
# $(SRC)/cmd/ctfmerge/%.c` rule and a makefile saying "build this one for the
# machine doing the build". See the standing order in ../default.nix.
#
# And built for ITS OWN host platform, with plain `stdenv`/`$CC`/`NIX_LDFLAGS`.
# `buildPackages.illumos.ctfmerge` is already an instance whose `stdenv`
# targets the build machine, so there is nothing to arrange: consumers put
# `ctfmerge` in `nativeBuildInputs` and splicing hands them that instance
# (uts-common.nix and libcMinimal.nix already do). `depsBuildBuild` with
# `$CC_FOR_BUILD` is for helpers a build runs and discards, never for the
# artifact being installed -- and reaching for it is what makes the gate
# makefile look unusable and invites hand-listing translation units instead.
mkDerivation {
  pname = "ctfmerge";
  path = "usr/src/cmd/ctfmerge";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    # <libctf.h> and, through it, <sys/ctf_api.h> and <sys/ctf.h>. illumos does
    # not ship these, so no host has a copy.
    "usr/src/lib/libctf/common"
    "usr/src/uts/common/sys"
    "usr/src/head"
  ];

  # The shared build-host overlay: SAVEARGS, the Solaris-ld flags GNU ld
  # rejects, the mapfile macros, STACKPROTECT and the post-processing no-ops.
  # Stated once in mkDerivation.nix rather than restated here -- restating it
  # per package is what grew the hand-written buildPhases this replaced.
  illumosNativeBuild = true;

  extraNativeBuildInputs = [ cw ];

  buildInputs = [
    libctf
    elfutils
  ];

  # libctf installs its shared object into `lib/$(MACH)` rather than `lib/`, so
  # cc-wrapper's `-L${libctf}/lib` from `buildInputs` does not find it. A wart
  # in libctf.nix -- its build-host form is still built out of
  # `tools/ctf/libctf`, which uses the onbld layout -- so name it explicitly.
  env.NIX_LDFLAGS = toString [
    "-L${libctf}/lib/i386"
    "-rpath"
    "${libctf}/lib/i386"
  ];

  # ctfmerge needs no libc gap-filler of its own -- it uses only pthreads, mmap
  # and libctf -- but still links `compat` for the shared `_sysconf`/`___errno`
  # shims, which cost nothing unreferenced. It is built here rather than shipped
  # built because compat_host.c must see the *consumer's* host headers;
  # mkfs-ufs.nix compiles it the same way.
  preBuild = ''
    $CC -c -o compat_host.o -D_GNU_SOURCE -D_LARGEFILE64_SOURCE \
      -I${compat.srcDir} "${compat.hostSource}"
    ar rcs libcompat.a compat_host.o
  '';

  makeFlags = [
    # illumos' MACH/MACH64 are not uname strings; on x86 they are i386/amd64.
    "MACH=i386"
    "MACH64=amd64"

    # cmd/ctfmerge has no amd64 subdirectory, so Makefile.cmd would build it
    # 32-bit. These are the contents of Makefile.master.64 restricted to what a
    # command build reads -- the same list getent.nix passes, and for the same
    # reason. `LDLIBS.cmd` rather than `LDLIBS`, because the package Makefile
    # appends `-lctf -lelf` to `LDLIBS` and a command-line macro would discard
    # them.
    "CFLAGS=$(CFLAGS64)"
    "ASFLAGS=$(ASFLAGS64)"
    "COMPILE.c=$(COMPILE64.c)"
    "LINK.c=$(LINK64.c)"
    "MAPFILECLASS=-64"

    # The headers illumos does not ship, plus the compat profiles that let gate
    # source compile against a foreign libc.
    #
    # `CPPFLAGS`, not `CPPFLAGS.first`: the shared overlay sets `CPPFLAGS` as a
    # command-line macro, and those outrank the makefile assignment that would
    # otherwise expand `$(CPPFLAGS.first)`. So `-D_TS_ERRNO` is carried through
    # here rather than lost.
    #
    # Ordering is load-bearing: `compat.hostElfCflags` must beat the staged
    # <sys/elf.h>, and `-idirafter` must lose to the host's own directories.
    # See compat/host-elf/sys/elf.h.
    "CPPFLAGS=-D_TS_ERRNO -D_LARGEFILE64_SOURCE ${compat.hostElfCflags} ${compat.stagedCflags} -I$(SRC)/lib/libctf/common -idirafter $(SRC)/uts/common -idirafter $(SRC)/head"

    # ...and libcompat, built in preBuild above.
    "LDLIBS.cmd=-L. -lcompat -lpthread"
  ];

  # `$(ROOTPROG)` is `$(ROOTBIN)/ctfmerge`, and the setup hook has already
  # rewritten `$(ROOT)/usr/bin` to `$(BINDIR)`; the directory still has to
  # exist before `$(INS.file)` runs.
  preInstall = ''
    mkdir -p $out/bin
  '';

  meta = {
    platforms = lib.platforms.unix;
    mainProgram = "ctfmerge";

    # Only the foreign-libc build is exercised. An illumos host needs none of
    # `compat` and wants sgs-libelf rather than elfutils, and nothing here
    # consumes a ctfmerge that runs on illumos.
    broken = stdenv.hostPlatform.isSunOS;
  };
}
