{
  lib,
  stdenvNoLibc,
  stdenvNoCC,
  makeScopeWithSplicing',
  generateSplicesForMkScope,
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
    }
  );
}
