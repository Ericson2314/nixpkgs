{
  lib,
  symlinkJoin,
  libcMinimal,
  libm,
  libpthread,
  libssp_ns,
  version,
}:

# The composite "libc" that the rest of nixpkgs means when it says slibc --
# same shape as netbsd/pkgs/libc.nix and freebsd/pkgs/libc. libcMinimal is
# only the bootstrap piece; things like gcc's libquadmath expect -lm to be
# available from the platform libc as well.
#
# illumos needs fewer parts than the BSDs here: libc.so.1 already implements
# the threads, rt and resolver interfaces that NetBSD splits into librt and
# libresolv. libpthread.so.1 is still included, but only as a *filter* library
# on libc -- it carries no code of its own, and exists so that an
# unconditional -lpthread (gcc's libsanitizer passes one) resolves.
symlinkJoin {
  pname = "libc-illumos";
  inherit version;

  outputs = [
    "out"
    "dev"
  ];

  paths =
    lib.concatMap
      (p: [
        (lib.getDev p)
        (lib.getLib p)
      ])
      [
        libcMinimal
        libm
        libpthread
        libssp_ns
      ];

  postBuild = ''
    rm -rf "$out/nix-support"
    fixupPhase
  '';

  meta.platforms = lib.platforms.illumos;
}
