{
  makeSetupHook,
  binutils,
  binutils-unwrapped,
}:

# See dt-needed-order-hook.sh for what is being checked and why.
#
# This lives outside ./pkgs so that `packagesFromDirectoryRecursive` does not
# pick it up into the illumos scope: the scope's *native* instance would give
# us the build machine's un-prefixed readelf, which cannot read an illumos
# object. The reader has to be the one that targets the cross system, so the
# hook is instantiated from pkgs/stdenv/cross/default.nix, where
# `buildPackages.binutils` is exactly that.
#
# The reader is passed in as a substitution, deliberately. `$READELF` is not
# exported into an illumos build, the target-prefixed binary is not on `$PATH`,
# and a derivation attribute (`ILLUMOS_READELF = ...`) does not survive into
# the build shell under `__structuredAttrs` -- it evaluates fine and is empty at
# run time.
makeSetupHook {
  name = "illumos-dt-needed-order-hook";
  substitutions = {
    readelf = "${binutils-unwrapped}/bin/${binutils.targetPrefix}readelf";
  };
  meta.description = "Reject illumos objects that list libc.so.1 before libgcc_s.so.1";
} ./dt-needed-order-hook.sh
