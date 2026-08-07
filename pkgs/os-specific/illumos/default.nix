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
      patchesRoot = ./patches;

      # TODO: build the real `libc.so.1` (with PICS, mapfile-vers and commpage)
      # and point this at it. Until then the bootstrap libc doubles as the final
      # one, which is enough to get the rest of the package set evaluating and
      # building, but is not a complete libc.
      libc = self.libcMinimal;

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

      head = self.callPackage ./pkgs/head.nix {
        inherit (buildPackages.netbsd) rpcgen;
      };
    }
  );
}
