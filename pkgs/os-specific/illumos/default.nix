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

      unix = self.callPackage ./pkgs/unix.nix {
        inherit (buildPackages.netbsd) rpcgen;
      };
    }
  );
}
