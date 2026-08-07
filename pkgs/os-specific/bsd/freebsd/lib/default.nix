{
  version,
  lib,
  filterPatches,
}:

let
  filterPatches' = filterPatches;
in

{
  inherit version;

  mkBsdArch =
    stdenv':
    {
      x86_64 = "amd64";
      aarch64 = "aarch64";
      i486 = "i386";
      i586 = "i386";
      i686 = "i386";
      armv6l = "armv6";
      armv7l = "armv7";
      powerpc = "powerpc";
      powerpc64 = "powerpc64";
      powerpc64le = "powerpc64le";
      riscv64 = "riscv64";
    }
    .${stdenv'.hostPlatform.parsed.cpu.name} or stdenv'.hostPlatform.parsed.cpu.name;

  mkBsdCpuArch =
    stdenv':
    {
      x86_64 = "amd64";
      aarch64 = "aarch64";
      i486 = "i386";
      i586 = "i386";
      i686 = "i386";
      armv6l = "arm";
      armv7l = "arm";
      powerpc = "powerpc";
      powerpc64 = "powerpc";
      powerpc64le = "powerpc";
      riscv64 = "riscv";
    }
    .${stdenv'.hostPlatform.parsed.cpu.name} or stdenv'.hostPlatform.parsed.cpu.name;

  mkBsdMachine =
    stdenv':
    {
      x86_64 = "amd64";
      aarch64 = "arm64";
      i486 = "i386";
      i586 = "i386";
      i686 = "i386";
      armv6l = "arm";
      armv7l = "arm";
      powerpc = "powerpc";
      powerpc64 = "powerpc";
      powerpc64le = "powerpc";
      riscv64 = "riscv";
    }
    .${stdenv'.hostPlatform.parsed.cpu.name} or stdenv'.hostPlatform.parsed.cpu.name;

  install-wrapper = builtins.readFile ../../lib/install-wrapper.sh;

  # See pkgs/build-support/filter-patches. The fragment name is pinned to its
  # historical value so that moving to the shared implementation does not
  # change any store path, and hence does not rebuild FreeBSD.
  filterPatches = filterPatches' { fragmentName = "freebsd-patch"; };
}
