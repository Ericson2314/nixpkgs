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

# ctfconvert(1): turn a compiler's DWARF into CTF. `genunix` cannot be built
# without it, and `unix` links against `libgenunix.so`, so this gates the whole
# kernel path.
#
# One attribute, one source file -- `usr/src/cmd/ctfconvert/ctfconvert.c` --
# and two ways of building it, chosen by the platform being built for. The
# platform comes from the package set, not from the name:
# `buildPackages.illumos.ctfconvert` is the build-host binary (the one every
# CTF-producing package here puts in `nativeBuildInputs`), and
# `illumos.ctfconvert` in a cross set is the illumos-hosted ctfconvert(1) that
# would ship. See ld.nix and libctf.nix, which have the same shape.
#
# This deliberately does NOT go through `usr/src/tools/ctf/ctfconvert`. That
# directory holds no source: it is `Makefile.com` plus a `%.o:
# $(SRC)/cmd/ctfconvert/%.c` rule, i.e. illumos' own way of saying "build this
# one for the machine doing the build". nixpkgs already says that, with
# `buildPackages`, and saying it twice is what the standing order in
# ../default.nix exists to stop. Nothing in ctfconvert.c is conditional on
# `NATIVE_BUILD`; the two builds differ only in which libc and which
# link-editor they use, which is exactly the difference splicing expresses.
let
  forIllumos = stdenv.hostPlatform.isSunOS;
in
mkDerivation (
  {
    pname = "ctfconvert";
    path = "usr/src/cmd/ctfconvert";
  }
  // (
    if forIllumos then
      {
        # The shipping ctfconvert(1) -- INCOMPLETE, and marked broken
        # accordingly; see `meta.broken` at the bottom.
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
        # The build-host binary. `noCC` plus the host compiler via
        # `depsBuildBuild`, like the rest of the CTF pipeline; see libdwarf.nix.
        noCC = true;

        extraPaths = [
          # <libctf.h> and, through it, <sys/ctf_api.h> and <sys/ctf.h>.
          # illumos does not ship these, so the host has no copy.
          "usr/src/lib/libctf/common"
          "usr/src/uts/common/sys"
          "usr/src/head"
        ];

        # One translation unit, one link. Running the gate makefile would only
        # be a way of arriving at this command line, and it cannot be run as
        # written: cmd/Makefile.cmd is an illumos-hosted, 32-bit,
        # illumos-ld-with-mapfiles build, which is precisely the set of
        # assumptions `tools/ctf/Makefile.ctf.native` exists to unpick. Doing
        # it here keeps the build-host variant expressed in nixpkgs.
        #
        # Include-path shape, which is load-bearing:
        #
        #  o `-D_LARGEFILE64_SOURCE` before anything else: <sys/ctf_api.h>
        #    declares `off64_t` fields, and glibc only defines that type under
        #    this feature-test macro.
        #
        #  o `compat.hostElfCflags` ahead of `compat.stagedCflags`, so that
        #    <sys/elf.h> forwards to the host's <elf.h> rather than resolving
        #    to illumos' own. libelf.h has already defined those types by the
        #    time <sys/ctf_api.h> asks for them; see host-elf/sys/elf.h.
        #
        #  o `compat.stagedCflags` for the rest -- the host's libc wins, with
        #    illumos' "_t" integer spellings and `boolean_t` layered on top.
        #    This is the same job `tools/ctf/native/native_compat.h` does
        #    upstream.
        #
        #  o `-I .../lib/libctf/common` for <libctf.h>, which exists nowhere
        #    else.
        #
        #  o `-idirafter` for `uts/common` and `head`: both hold headers
        #    illumos does not ship (<sys/ctf_api.h>, <sys/debug.h>) *and*
        #    headers every libc has (<sys/types.h>). Searched after the host's
        #    own directories, the host wins wherever it has an opinion and
        #    illumos supplies the rest. Upstream's Makefile.ctf.native reaches
        #    the same conclusion, in the same way.
        #
        # `compat.hostSource` is in the link for `strtonum(3C)`: ctfconvert
        # parses `-j` and `-m` with it, and glibc has no such function. That is
        # what the `compat` package is for -- a gap in a foreign libc, filled
        # on the host side rather than by patching the gate.
        buildPhase = ''
          runHook preBuild

          # Compiled on its own, and with its own flags: compat_host.c is by
          # construction a *host*-headers translation unit, and it needs the
          # glibc-specific spellings (`stat64`, `statvfs64`) that those two
          # macros unlock. mkfs-ufs.nix compiles it the same way.
          $CC_FOR_BUILD -c -o compat_host.o -D_GNU_SOURCE -D_LARGEFILE64_SOURCE \
            -I${compat.srcDir} "${compat.hostSource}"

          $CC_FOR_BUILD -o ctfconvert \
            -D_LARGEFILE64_SOURCE \
            ${compat.hostElfCflags} ${compat.stagedCflags} \
            -I "$SRC/lib/libctf/common" \
            -idirafter "$SRC/uts/common" \
            -idirafter "$SRC/head" \
            ctfconvert.c compat_host.o \
            -lctf -lelf

          runHook postBuild
        '';

        # `install` on $PATH here is illumos' install(1), whose options are not
        # GNU coreutils'.
        installPhase = ''
          runHook preInstall

          mkdir -p $out/bin
          cp ctfconvert $out/bin/ctfconvert

          runHook postInstall
        '';

        # libctf and libdwarf install into lib/$(MACH), which is not the lib/
        # that cc-wrapper picks up from a depsBuildBuild entry, so point at them
        # by hand. These are the build-platform spellings of NIX_LDFLAGS.
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
      mainProgram = "ctfconvert";

      # The illumos-hosted branch is untested: nothing here consumes a
      # ctfconvert that runs on illumos, and the cmd/Makefile.cmd link path has
      # the same GNU-ld-versus-`-Bdirect` problem documented in ld.nix. Marked
      # broken rather than left to return a plausible-looking binary -- the
      # previous shape of this file had `noCC` unconditionally and so answered
      # `pkgsCross.x86_64-illumos.illumos.ctfconvert` with a *Linux* binary.
      broken = forIllumos;
    };
  }
)
