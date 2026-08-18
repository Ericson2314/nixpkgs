{
  lib,
  stdenv,
  mkDerivation,

  compat,
  libdwarf,
  libctf,

  buildPackages,

  # Only used by the illumos-hosted build; see the split at the bottom.
  cw,
  headers,
  sgs-libelf,
}:

# ctfmerge(1): merge per-object CTF containers into one and write the result
# back into the linked object. The other half of the CTF pipeline; see
# ctfconvert.nix, which this mirrors exactly -- one source file
# (`usr/src/cmd/ctfmerge/ctfmerge.c`), one attribute, and a `forIllumos` split
# choosing between the build-host binary and the illumos-hosted one.
#
# As there, `usr/src/tools/ctf/ctfmerge` is deliberately not used: it contains
# no source, only illumos' own spelling of "build this for the machine doing
# the build", which is what `buildPackages` says here. See the standing order
# in ../default.nix.
#
# Unlike ctfconvert this one needs no libc gap-fillers of its own -- it uses
# only pthreads, mmap and the CTF library -- but it is still linked against
# `compat.hostSource` for the shared `_sysconf`/`___errno` shims, which cost
# nothing when unreferenced.
let
  forIllumos = stdenv.hostPlatform.isSunOS;
in
mkDerivation (
  {
    pname = "ctfmerge";
    path = "usr/src/cmd/ctfmerge";
  }
  // (
    if forIllumos then
      {
        # The shipping ctfmerge(1) -- INCOMPLETE; see `meta.broken` below.
        libcMinimal = true;

        extraPaths = [
          "usr/src/Makefile.master"
          "usr/src/Makefile.master.64"
          "usr/src/Makefile.native"
          "usr/src/Makefile.smatch"

          "usr/src/cmd/Makefile.cmd"
          "usr/src/cmd/Makefile.cmd.64"
          "usr/src/cmd/Makefile.ctf"
          "usr/src/cmd/Makefile.targ"

          "usr/src/lib/libctf/common"
          "usr/src/common/ctf"
          "usr/src/uts/common/sys"
          "usr/src/head"
        ];

        extraNativeBuildInputs = [ cw ];

        buildInputs = [
          headers
          libctf
          sgs-libelf
        ];

        makeFlags = [
          "MACH=i386"
          "MACH64=amd64"
        ];
      }
    else
      {
        noCC = true;

        extraPaths = [
          "usr/src/lib/libctf/common"
          "usr/src/uts/common/sys"
          "usr/src/head"
        ];

        # See ctfconvert.nix for why this is a compiler invocation rather than
        # a `make`, and for what each of the include flags is doing.
        # `-lpthread` is the only difference: ctfmerge is threaded (`-j`).
        buildPhase = ''
          runHook preBuild

          # See ctfconvert.nix for why this is compiled separately.
          $CC_FOR_BUILD -c -o compat_host.o -D_GNU_SOURCE -D_LARGEFILE64_SOURCE \
            -I${compat.srcDir} "${compat.hostSource}"

          $CC_FOR_BUILD -o ctfmerge \
            -D_LARGEFILE64_SOURCE \
            ${compat.hostElfCflags} ${compat.stagedCflags} \
            -I "$SRC/lib/libctf/common" \
            -idirafter "$SRC/uts/common" \
            -idirafter "$SRC/head" \
            ctfmerge.c compat_host.o \
            -lctf -lelf -lpthread

          runHook postBuild
        '';

        # `install` on $PATH here is illumos' install(1), whose options are not
        # GNU coreutils'.
        installPhase = ''
          runHook preInstall

          mkdir -p $out/bin
          cp ctfmerge $out/bin/ctfmerge

          runHook postInstall
        '';

        NIX_LDFLAGS_FOR_BUILD = toString [
          "-L${libctf}/lib/i386"
          "-rpath"
          "${libctf}/lib/i386"
          "-L${libdwarf}/lib/i386"
          "-rpath"
          "${libdwarf}/lib/i386"
        ];

        depsBuildBuild = [
          buildPackages.stdenv.cc
          buildPackages.elfutils
          buildPackages.zlib
        ];
      }
  )
  // {
    meta = {
      platforms = lib.platforms.unix;
      mainProgram = "ctfmerge";

      # See ctfconvert.nix: untested, unconsumed, and honest about it rather
      # than quietly handing back a Linux binary under an illumos-host name.
      broken = forIllumos;
    };
  }
)
