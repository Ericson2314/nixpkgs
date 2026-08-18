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
#
# REFINEMENT, learned the hard way: the rule is about duplicated SOURCE, not
# about the path a makefile happens to live under. `tools/ctf/ctfconvert` and
# `tools/ctf/ctfmerge` are NOT second copies of those programs --
# `tools/ctf/ctfconvert/Makefile.com` compiles `$(SRC)/cmd/ctfconvert/%.c`, the
# same source, with no `NATIVE_BUILD` conditional anywhere. What lives under
# `tools/` there is a MAKEFILE SHIM (`Makefile.ctf.native`), and it is shared
# with `libctf` and `libdwarf` besides. Replacing it with a hand-written nix
# recipe would ADD a source of truth rather than remove one, so those two stay.
#
# So: migrate when `tools/` holds a second COPY of the program. Leave it alone
# when `tools/` merely holds a different way to build the same file.
#
# It IS true of `ld`, whose `native` variant exists only to get a build-host
# binary of sources that already build from `cmd/sgs/ld` for the target. If you find
# yourself adding a `native = { path = "usr/src/tools/...` variant to a package
# whose sources live under `cmd/`, that is the smell this order exists to
# catch: build the `cmd/` sources for the build platform instead.
#
{
  lib,
  stdenvNoLibc,
  stdenvNoCC,
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
    lib.packagesFromDirectoryRecursive {
      callPackage = self.callPackage;
      directory = ./pkgs;
    }
    // {
      version = "2.11";

      # Patches are generated from commits on the illumos-gate `nix-cross`
      # branch by ./update-patches.sh; that branch is the source of truth.
      #
      # The whole directory is one `git format-patch` of that one branch
      # against the revision `./pkgs/source.nix` pins, and nothing else. Do not
      # add a patch here by hand, or take one from another branch: the script
      # starts by deleting `patches/*.patch`, so anything not on `nix-cross`
      # is silently lost the next time anyone regenerates.
      patchesRoot = ./patches;

      stdenvLibcMinimal = stdenvNoLibc.override (old: {
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
