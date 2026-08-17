# ITERATION HARNESS. NEVER THE DEFAULT PATH, AND NEVER A BUILD ANYONE RELIES ON.
#
# The problem it solves. Every component of the `ng` set is built from ONE
# source -- the whole GCC monorepo -- so editing `fixincludes/` changes the src
# hash and invalidates `gcc` too. `gcc` is a ~1.5h build and everything
# downstream of it is seconds. Naively debugging `fixincludes`, `target-specs`,
# `include-fixed`, `gcc-composed` or `libgcc` therefore costs a compiler rebuild
# per edit, which is not a debug cycle at all.
#
# So: pin the compiler to an output that is ALREADY BUILT, and let everything
# downstream take the working tree.
#
#     nix-build mt-debug.nix -A gccNGPackages_17.include-fixed
#     nix-build mt-debug.nix -A gccNGPackages_17.target-specs
#     nix-build mt-debug.nix -A pkgsCross.aarch64-multiplatform.gccNGPackages_17.gcc-composed
#
# WHAT MAKES THIS A LIE, AND WHY THAT IS ACCEPTABLE HERE BUT NOWHERE ELSE. The
# pinned path was built from SOME revision of the source, and nothing checks it
# against the one being edited. If you change `gcc/` and build through this
# file, you get the old compiler and no diagnostic -- which is precisely the
# "absent artefact vs absent mechanism" shape this project keeps paying for. It
# is tolerable only because the pin is explicit, opt-in, and lives in a file
# whose name says so. Anything you intend to believe, build through `./.`.
#
# The `pinnedGcc` default is stale the moment the branch moves. It is a
# parameter so that you can say which one you mean:
#
#     nix-build mt-debug.nix --argstr pinnedGcc /nix/store/...-gcc-17.0.0-... \
#       -A gccNGPackages_17.include-fixed
#
# HOW THE PIN REACHES EVERYTHING. It is an overlay, not an `override` at one use
# site, because `all-packages.nix:91-92` and `:104-108` build the stdenv from
# `buildPackages.gccNGPackages.*` on a `useGccNG` platform. An override applied
# to one package set would leave the `buildPackages` instance -- and therefore
# the stdenv -- pulling an unpinned compiler, and the rebuild would come back
# without saying so. Overlays are propagated to every package set nixpkgs
# derives, `buildPackages` included, so this reaches all of them.
#
# The pin is `drv // { outPath = ...; }` rather than a bare `builtins.storePath`
# on purpose: consumers read `passthru` off this derivation (`langC`, `langCC`
# and friends in `gcc-composed`), and a bare store path is a string with none of
# that. Overriding `outPath` alone keeps the attribute set intact while making
# every `${gcc-unwrapped}` interpolation -- and every dependency edge nix
# records from it -- point at the built output.
#
# AND THE OTHER HALF: `srcDir`. Pinning the compiler is not enough on its own,
# because the source is a `fetchgit` of a COMMITTED revision -- so an edit under
# `fixincludes/` in a working tree changes nothing at all until it is committed
# and the rev and hash are bumped, which is a worse cycle than the rebuild.
# Point `srcDir` at the GCC working tree and every component takes it directly:
#
#     nix-build mt-debug.nix --argstr srcDir /home/jcericson/src/gnu/gcc/multi-target \
#       -A gccNGPackages_17.include-fixed
#
# `builtins.path` copies at EVALUATION time, as the invoking user, so it also
# sidesteps the sandbox: no mirror, no `extra-sandbox-paths`. It also means
# uncommitted state goes into a store path, which is exactly what the real
# expression refuses to do and exactly what iteration needs.
{
  pinnedGcc ? "/nix/store/1fh1xwb3pwyqgzh9414v3qvywbgp4g40-gcc-17.0.0-multi-target-1167d3f",
  srcDir ? null,
  ...
}@args:
let
  lib = import ./lib;
  localSrc = builtins.path {
    name = "multi-target-worktree";
    path = srcDir;
    # `.git` is most of the bytes and none of the build. Excluding it also stops
    # every `git` operation in the tree from changing the store path.
    filter = path: _type: baseNameOf path != ".git";
  };

  srcOverlay = final: prev: {
    gccNGPackages_17 =
      (prev.callPackages ./pkgs/development/compilers/gcc/ng {
        gccVersions."17.0.0" = {
          name = "17";
          # `gitRelease` is kept, and only for `rev-version`: it is what makes
          # the derivations still call themselves `-multi-target-<rev>`. The
          # `rev` in it is NOT what is built -- `monorepoSrc` below wins -- so
          # the name is a LIE under this file, deliberately and only here.
          gitRelease = {
            rev = "0000000000000000000000000000000000000000";
            version = "17.0.0";
            rev-version = "17.0.0-multi-target-WORKTREE";
          };
          monorepoSrc = localSrc;
        };
      })."17";
  };

  pinOverlay = final: prev: {

    gccNGPackages_17 = prev.gccNGPackages_17.overrideScope (
      _gccFinal: gccPrev: {
        gcc-unwrapped = gccPrev.gcc-unwrapped // {
          outPath = builtins.storePath pinnedGcc;
        };
      }
    );
  };

  # `gccNGPackages` is a second name for the same set (`all-packages.nix:3260`),
  # and it is the one the stdenv construction uses. Aliasing it to the pinned
  # `_17` here rather than pinning it separately keeps one authority for the
  # pin -- two independently pinned sets would be two compilers with one name,
  # which is the defect this whole branch exists to remove.
  aliasOverlay = final: prev: {
    gccNGPackages = final.gccNGPackages_17;
  };
in
import ./. (
  builtins.removeAttrs args [
    "pinnedGcc"
    "srcDir"
  ]
  // {
    # ORDER MATTERS AND IS NOT ARBITRARY. `srcOverlay` REPLACES the set (it
    # re-calls the whole `ng` expression with a different source), so a pin
    # applied before it would be thrown away silently -- the build would come
    # back, correct and slow, with nothing saying why. `pinOverlay` therefore
    # runs after, on whichever set `srcOverlay` left behind.
    overlays =
      (args.overlays or [ ])
      ++ lib.optional (srcDir != null) srcOverlay
      ++ [
        pinOverlay
        aliasOverlay
      ];
  }
)
