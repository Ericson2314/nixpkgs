# Does the compiler depend on the target?
#
# Ask two different cross package sets for the compiler that runs on the build
# machine. Which cross set the question was asked through should not matter at
# all: the compiler serves a *list* of back ends, and that list is a property of
# the compiler, not of whichever platform someone happened to be building for.
#
# Same store path  => nothing target-specific is left in the derivation.
# Paths differ     => something still is, and the .drv diff says what.
#
#   nix-instantiate mt-compare.nix -A same.aarch64
#   nix-instantiate mt-compare.nix -A same.netbsd
#
# NOTHING IS PINNED IN `same'. An earlier version of this file passed the same
# `enableTargets` list to both sides, which is a weaker question than it looks:
# it asks "given identical inputs, are the outputs identical", which is true of
# any derivation whatsoever. The real question is whether the *default* inputs
# are the same, and that is what `same' now asks.
#
# `differ' exists because a check that can only report "pass" reports nothing.
# It pins a deliberately different list on each side, so the two paths MUST
# diverge. Run it on the same tree as `same': if `differ' also comes out equal,
# the instrument is broken and `same' proved nothing.
#
#   nix-instantiate mt-compare.nix -A differ.aarch64
#   nix-instantiate mt-compare.nix -A differ.netbsd
let
  pkgsFor = crossConfig: import ./. { crossSystem = { config = crossConfig; }; };

  crossSets = {
    aarch64 = "aarch64-unknown-linux-gnu";
    netbsd = "x86_64-unknown-netbsd";
    # Cygwin, because `enableTargetShared` still reads `targetPlatform` and
    # Cygwin is the one platform its condition singles out.  Without an arm
    # that exercises a *different* answer, that reference would go unmeasured.
    cygwin = "x86_64-pc-cygwin";
  };

  compiler =
    crossConfig: args:
    let
      c = (pkgsFor crossConfig).buildPackages.gccNGPackages_17.gcc-unwrapped;
    in
    if args == null then c else c.override args;
in
{
  # THE TEST. No overrides on either side.
  same = builtins.mapAttrs (_: cfg: compiler cfg null) crossSets;

  # THE CONTROL. Different list per side, so the paths must differ. If they do
  # not, `same' above is not measuring anything.
  differ = {
    aarch64 = compiler crossSets.aarch64 {
      enableBackends = [ "aarch64-unknown-linux-gnu" ];
    };
    netbsd = compiler crossSets.netbsd {
      enableBackends = [ "x86_64-pc-linux-gnu" ];
    };
  };
}
