{
  lib,
  symlinkJoin,
  libcMinimal,
  libm,
  libpthread,
  libssp_ns,
  rtld,
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
        # ld.so.1. The bintools wrapper points PT_INTERP at
        # "${libc}/lib/64/ld.so.1" (bintools-wrapper/default.nix:163), so the
        # runtime linker has to be reachable through the composite or nothing
        # dynamically linked has an interpreter to run at all.
        rtld
      ];

  postBuild = ''
    rm -rf "$out/nix-support"

    # illumos names the 64-bit runtime linker directory "64", and on x86 that is
    # a symlink to "amd64" -- which is where rtld installs and what its SONAME
    # and every PT_INTERP say. Provide the alias the wrapper expects.
    if [ ! -e "$out/lib/64" ]; then
      ln -s amd64 "$out/lib/64"
    fi

    fixupPhase
  '';

  meta.platforms = lib.platforms.illumos;
}
