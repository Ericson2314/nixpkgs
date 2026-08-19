# The illumos package set.
#
# STANDING ORDER: package from `usr/src/cmd/` (and `usr/src/lib/`,
# `usr/src/uts/`), NOT from `usr/src/tools/`.
#
# `usr/src/tools/` is illumos' own bootstrap-tools tree: the same programs
# rebuilt with `-DNATIVE_BUILD` against a `native_compat.h` shim so they can run
# on the machine doing the build. We do not need that. nixpkgs already
# expresses "the same derivation, built for the build platform" -- that is what
# the splicing below is for, and `buildPackages.illumos.foo` is how you ask for
# it. Reaching into `tools/` instead means maintaining illumos' answer to a
# problem nixpkgs has already solved, and keeping a second copy of a program
# that can drift from the first.
#
# The only acceptable reason to use `tools/` is that the program EXISTS ONLY
# THERE and cannot be obtained any other way. As of writing that is true of:
#
#   cw        illumos' compiler wrapper. No `cmd/cw`; it is a build tool by
#             nature and has no target-side existence.
#   ctfstabs  only `tools/ctf/stabs`; no `cmd/` counterpart.
#   sgsmsg    only `tools/sgs/sgsmsg/sgsmsg.c`. `cmd/sgs/include/sgsmsg.h` is
#             the header alone -- the program exists nowhere else. It generates
#             the sgs message catalogues, so libconv and the rest of cmd/sgs
#             need it to build at all. Splitting it out of the `tools/sgs`
#             aggregate is the first step to freeing `ld.nix` from that
#             aggregate.
#
# and it is NOT true of `ctfconvert`, `ctfmerge` or `ld`, all of which exist
# under `cmd/` and should come from there for both platforms.
#
# "But `tools/ctf` is only a makefile, not a second copy of the source" is not
# a reason to keep it -- it is the reason to drop it. `Makefile.ctf.native` is
# illumos' answer to "build this for the machine doing the build", and
# splicing is ours. Using theirs means the build-host variant of a package is
# expressed in illumos' build system instead of in nixpkgs, where every other
# package in the tree expresses it. That the duplication is a makefile rather
# than a `.c` file makes it cheaper to delete, not more defensible to keep.
#
# If you find yourself adding a `native = { path = "usr/src/tools/..."; }`
# variant to a package whose sources live under `cmd/`, that is the smell this
# order exists to catch: build the `cmd/` sources for the build platform
# instead, with `buildPackages.illumos.<pkg>`.

#
# STANDING ORDER: no `#` comments inside a Nix multiline string (`''...''`).
#
# Inside `''...''` a `#` is not a Nix comment. It is literal text that becomes
# part of the string. In a `buildCommand` or a `preBuild` it survives into the
# shell script -- where it happens to be a shell comment, which is exactly what
# makes the mistake invisible. Anywhere the string is not shell (a config file,
# a manifest, a makefile fragment, generated C) it lands in the output verbatim.
#
# It also makes the prose part of the derivation: rewording a comment changes
# the hash and rebuilds the package and everything downstream of it. Comments
# should be free to edit.
#
# Put the commentary in Nix comments *outside* the string, above the attribute.
# Where a note genuinely belongs in the generated artefact, write it in that
# artefact's own comment syntax on purpose, and say why.
#
{
  lib,
  stdenv,
  stdenvNoLibc,
  stdenvNoCC,
  elfutils,
  makeScopeWithSplicing',
  generateSplicesForMkScope,
  buildPackages,
}:

let
  otherSplices = generateSplicesForMkScope "illumos";
  buildIllumos = otherSplices.selfBuildHost;
in

makeScopeWithSplicing' {
  inherit otherSplices;
  f = (
    self:
    let
      # Give a stdenv the illumos link-editor in place of GNU ld.
      #
      # This is the whole of the scoping decision, and it is deliberate that it
      # lives here rather than in `lib/systems/default.nix`. A platform-level
      # `linker = "illumos"` would hand illumos ld to *every* package nixpkgs
      # builds for this target, and illumos ld is not a drop-in for GNU ld on
      # arbitrary third-party source: measured on the nixbsd `illumos-full` VM,
      # that broke boost, coreutils, gtest, libxcrypt, libxslt, ncurses and
      # openssl, in four unrelated ways (see ./pkgs/illumos-ld.sh). None of that
      # buys the gate anything, because the gate is the only thing that needs
      # this link-editor.
      #
      # One of those four ways -- the ld bug behind gtest and boost -- has since
      # been root-caused and fixed (patch 0070 in ./patches). Re-measured with
      # the fixed ld, gtest and boost build clean and the other five still fail
      # exactly as before: GNU version scripts fed to `-M` (libxslt, libxcrypt),
      # a GNU-only option desynchronising getopt(3) (ncurses), and compressed
      # debug sections ld cannot relocate (coreutils, openssl). Three separate
      # defects, none of them in ld's relocation engine, all of them still
      # blocking. So the scoping stays.
      #
      # Two mechanical things also stand in the way, and are worth knowing
      # before anyone tries again:
      #
      #  o	`bintools-unwrapped` in all-packages is not what the cross stdenv's
      #	cc uses. illumos sets `useGccNG`, and `gcc/ng` takes `binutils` /
      #	`binutilsNoLibc` -- always the GNU pair -- not the picker's
      #	`bintools` / `bintoolsNoLibc`. Setting `linker = "illumos"` and adding
      #	the branch to `bintools-unwrapped` evaluates fine and changes
      #	`bintools`, while `stdenv.cc.bintools.bintools` stays GNU binutils.
      #	Verified. Teaching `gcc/ng` to consult the picker is the real
      #	prerequisite, and it is a change for every platform, not this one.
      #
      #  o	`./pkgs/bintools.nix` below takes `binutils-unwrapped` from
      #	`stdenv.cc.bintools.bintools`. Under a picker that lands this very
      #	derivation there, that is infinite recursion -- it is, verbatim, the
      #	error you get. It would have to take the plain `binutils-unwrapped`
      #	of the same stage instead.
      #
      # So: illumos ld for the gate, GNU ld for everyone else. The gate keeps
      # the mapfiles, `-Bdirect` and `.SUNW_*` sections it cannot build without,
      # and the rest of nixpkgs keeps the linker it was written for.
      #
      # Only for illumos-hosted builds. `buildPackages.illumos.*` -- `cw`,
      # `make`, `install`, `ld` itself -- are Linux binaries built from gate
      # source to run the cross build; they link with the build platform's own
      # toolchain, and overriding them here would be both wrong and circular,
      # since `self.bintools` is built out of `buildIllumos.ld`.
      withIllumosLd =
        stdenv:
        if !stdenvNoCC.hostPlatform.isIllumos then
          stdenv
        else
          stdenv.override (old: {
            cc = old.cc.override (ccOld: {
              bintools = ccOld.bintools.override { bintools = self.bintools; };
            });
          });
    in
    lib.packagesFromDirectoryRecursive {
      callPackage = self.callPackage;
      directory = ./pkgs;
    }
    // {
      version = "2.11";

      # --------------------------------------------------------------------
      # The host-platform test, stated ONCE for the whole set.
      #
      # Packages here must not ask `stdenv.hostPlatform.isSunOS` themselves.
      # That is what `forIllumos` was, and a package that branches on it stops
      # being one definition with two instances and becomes two packages
      # sharing a filename -- which is how `libctf` and `libdwarf` ended up
      # pointing at two entirely different source trees.
      #
      # The BSD trees model the same thing with `compatIsNeeded` /
      # `compatIfNeeded` (see pkgs/os-specific/bsd/freebsd/package-set.nix):
      # the scope decides, the package consumes a value. `f` is evaluated once
      # per spliced instance, so these are per-platform exactly as they should
      # be.
      # --------------------------------------------------------------------

      # True when gate source is being compiled against a foreign libc, i.e.
      # for the machine doing the build rather than for illumos.
      compatIsNeeded = !stdenvNoCC.hostPlatform.isIllumos;
      compatIfNeeded = lib.optional self.compatIsNeeded self.libcompat;

      # `-lelf`. illumos' own libelf lives in the link-editor's source tree
      # and only exists for illumos; a foreign host has elfutils'.
      libelf = if self.compatIsNeeded then elfutils else self.sgs-libelf;

      # What it takes to COMPILE gate library sources on this host.
      #
      # On a foreign host that means the "staged" compat profile --
      # `native_compat.h` force-included, supplying the illumos type
      # vocabulary the gate headers assume -- and then the gate's own headers
      # searched AFTER the host's, so the host wins wherever it has an opinion
      # and illumos supplies only what the host has no equivalent of. Ordering
      # is load-bearing; see libcompat.nix.
      #
      # `-DCTF_NATIVE_COMPAT` is part of the same statement and is NOT optional.
      # It is the gate's own name for "this translation unit is being compiled
      # against a foreign libc", and the guards it controls are load-bearing:
      # lib/libctf/common/ctf_lib.c gives `_libctf_init` a `__constructor__`
      # attribute, because `#pragma init` is a Studio directive that gcc ignores
      # SILENTLY -- leaving `_PAGEMASK` at 0, so `ctf_sect_munmap()` unmaps from
      # address 0 and takes the heap with it. That is a segfault deep inside
      # ctfstabs, surfacing as a kernel build failure in `genoffsets`.
      # ctf_elfwrite.c uses it for `ELF_F_PERMISSIVE` on the same grounds.
      #
      # On illumos all of this is empty: the headers are simply the platform's
      # own and the pragma is honoured.
      #
      # `extra` is for the handful of macros a single library adds to the same
      # `CPPFLAGS.first`, which cannot be a second `makeFlags` entry because a
      # command-line macro is assigned, not appended.
      #
      # `hostElf`: for a library that also includes the host's <libelf.h>. The
      # staged <sys/elf.h> and elfutils' own ELF types are the same structs
      # declared twice, so they cannot both be visible; `hostElfCflags` wins
      # ahead of the staged set and defers to the host. See tools/libcompat/host-elf.
      compatMakeFlags =
        {
          extra ? [ ],
          hostElf ? false,
        }:
        lib.optional self.compatIsNeeded (
          "CPPFLAGS.first=-D_LARGEFILE64_SOURCE -DCTF_NATIVE_COMPAT "
          + lib.optionalString hostElf "${self.libcompat.hostElfCflags} "
          + "${self.libcompat.stagedCflags} ${toString extra}"
          + " -idirafter $(SRC)/uts/common -idirafter $(SRC)/head"
        );

      # What it takes to LINK a `usr/src/lib/*` shared object.
      #
      # On illumos that is illumos' own link-editor invoked directly -- see
      # libm.nix for why the compiler driver cannot do it -- against the
      # gate's crt and its minimal libc, with `-L`/`-R` for every library
      # named in `libs`.
      #
      # On the build host it is nothing at all: GNU ld and the host libc do
      # the job, and mkDerivation's build-host overlay has already emptied
      # every Solaris-only macro (`MAPFILE.*`, the `Z*` options, `SAVEARGS`)
      # that would otherwise reach it. So the whole apparatus simply is not
      # there, rather than being conditionalised at each use.
      #
      # Returns attributes to merge into an mkDerivation call: `buildInputs`,
      # `cflags` (a list, for the package to concatenate into its own
      # NIX_CFLAGS_COMPILE) and `preBuild`.
      sharedLink =
        {
          libs ? [ ],
          # Set for a library whose own `Makefile` already names crti/crtn.
          crtFiles ? true,
        }:
        if self.compatIsNeeded then
          {
            buildInputs = libs;
            cflags = [ ];
            preBuild = "";
          }
        else
          let
            crtStart = lib.optionalString crtFiles "${self.crt}/lib/crti.o ";
            crtEnd = lib.optionalString crtFiles " ${self.crt}/lib/crtn.o";
            libPaths = lib.concatMapStrings (l: " -L${l}/lib -R${l}/lib") libs;
          in
          {
            buildInputs = [
              self.headers
              self.crt
              self.libcMinimal
            ]
            ++ libs;
            cflags = [ "-B${self.crt}/lib" ];
            preBuild = ''
              makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crtStart}\$(PICS) \$(EXTPICS)${crtEnd} -L${self.libcMinimal}/lib -L${self.libssp_ns}/lib${libPaths} \$(LDLIBS)")
            '';
          };

      # Patches are generated from commits on the illumos-gate `virtiofs`
      # branch by ./update-patches.sh; that branch is the source of truth.
      #
      # The whole directory is one `git format-patch` of that one branch
      # against the revision `./pkgs/source.nix` pins, and nothing else. Do not
      # add a patch here by hand, or take one from another branch: the script
      # starts by deleting `patches/*.patch`, so anything not on `virtiofs`
      # is silently lost the next time anyone regenerates.
      #
      # NOTE THE BRANCH. This said `nix-cross` until it was caught, and the
      # script defaulted to it too -- while `patches/` had in fact been
      # generated from `virtiofs`, which is `nix-cross` plus ten commits (the
      # Virtio-FS client, the krtld empty-relocation fix, the idmap header
      # path, `lowbit64()`). Regenerating the documented way would have deleted
      # every one of them: 31 commits on `nix-cross` against 41 patches here.
      # Caught only by counting. If the branches are ever merged or renamed,
      # fix this comment and the script default together.
      patchesRoot = ./patches;

      # GNU binutils with illumos' link-editor substituted for GNU ld; see
      # ./pkgs/bintools.nix. Both arguments have to be named explicitly, because
      # the defaults `callPackage` would supply are wrong in opposite ways:
      #
      #  o	`binutils-unwrapped` must be the *cross* binutils this package set
      #	already uses -- host is the build machine, target is illumos -- so
      #	that its programs carry the `x86_64-unknown-solaris2.11-` prefix
      #	bintools-wrapper looks for. That is the one inside the stdenv's own
      #	wrapper, not the scope's or the top level's.
      #
      #  o	`ld` must be the link-editor that *runs on the build machine*.
      #	`self.ld` in a cross set is an illumos-hosted binary, which cannot be
      #	executed here; `buildIllumos.ld` is illumos' own tools/sgs bootstrap
      #	build of the same sources. See ./pkgs/ld.nix on why one attribute
      #	covers both.
      bintools = self.callPackage ./pkgs/bintools.nix {
        binutils-unwrapped = stdenv.cc.bintools.bintools;
        ld = buildIllumos.ld;

        # The `#!` of a script collect2 runs on the machine doing the build, so
        # it is the build platform's shell. The scope's own `runtimeShell` is
        # illumos' bash, which is built with the very stdenv this feeds -- and
        # taking it would be a cycle, not merely an unrunnable interpreter.
        runtimeShell = buildPackages.runtimeShell;
      };

      # The stdenvs every package in this scope gets, shadowing the top-level
      # ones. `stdenvNoCC` is deliberately not among them: with no compiler
      # there is nothing to link, so overriding it would only churn hashes.
      stdenv = withIllumosLd stdenv;
      stdenvNoLibc = withIllumosLd stdenvNoLibc;

      stdenvLibcMinimal = self.stdenvNoLibc.override (old: {
        cc = old.cc.override {
          libc = self.libcMinimal;
          noLibc = false;
          bintools = old.cc.bintools.override {
            libc = self.libcMinimal;
            noLibc = false;
            sharedLibraryLoader = null;
          };
        };
      });

      uts-headers = self.callPackage ./pkgs/uts-headers.nix {
        inherit (buildPackages.netbsd) rpcgen;
      };

      head = self.callPackage ./pkgs/head.nix {
        inherit (buildPackages.netbsd) rpcgen;
      };

      # The shared build environment behind `uts-base` and every `kmod`; it is
      # where the uts makefiles' use of rpcgen lives. `unix` itself now only
      # assembles those outputs and needs no tools of its own.
      #
      # The `removeAttrs`: this is a plain attrset of mkDerivation arguments,
      # not a package, and callPackage decorates every attrset it returns with
      # `override` and `overrideDerivation`. Its consumers splice this set into
      # mkDerivation, where a stray function-valued attribute becomes an attempt
      # to turn it into an environment variable ("cannot coerce a set to a
      # string").
      uts-common =
        removeAttrs
          (self.callPackage ./pkgs/uts-common.nix {
            inherit (buildPackages.netbsd) rpcgen;
          })
          [
            "override"
            "overrideDerivation"
          ];
    }
  );
}
