# Does the compiler depend on the target?
#
# Ask two different cross package sets for the compiler that runs on the build
# machine, pinning the same `enableTargets` in both. The target list is the only
# thing that should decide what the compiler is; which cross set the question was
# asked through should not matter at all.
#
# Same store path  => nothing target-specific is left in the derivation.
# Paths differ     => something still is, and the .drv diff says what.
#
#   nix-instantiate mt-compare.nix -A aarch64
#   nix-instantiate mt-compare.nix -A netbsd
let
  targets = [ "x86_64-unknown-linux-gnu" ];

  compilerFor =
    crossConfig:
    let
      pkgs = import ./. { crossSystem = { config = crossConfig; }; };
    in
    pkgs.buildPackages.gccNGPackages_15.gcc-unwrapped.override {
      enableTargets = targets;
    };
in
{
  aarch64 = compilerFor "aarch64-unknown-linux-gnu";
  netbsd = compilerFor "x86_64-unknown-netbsd";
}
