{
  lib,
  symlinkJoin,
  libcMinimal,
  libm,
  libpthread,
  libssp_ns,
  rtld,
  libdl,
  libsocket,
  libnsl,
  libmd,
  libmp,
  libnvpair,
  version,
}:

# The composite "libc" that the rest of nixpkgs means when it says slibc --
# same shape as netbsd/pkgs/libc.nix and freebsd/pkgs/libc. libcMinimal is
# only the bootstrap piece; things like gcc's libquadmath expect -lm to be
# available from the platform libc as well.
#
# libc.so.1 already implements the threads and rt interfaces that NetBSD splits
# into librt; libpthread.so.1 is still included, but only as a *filter* library
# on libc -- it carries no code of its own, and exists so that an
# unconditional -lpthread (gcc's libsanitizer passes one) resolves. libdl.so.1
# is a filter for the same reason, on ld.so.1.
#
# It does *not* implement sockets or the resolver, contrary to an assumption
# that cost us a while: `socket`, `connect`, `getaddrinfo` and `gethostbyname`
# are all absent from libc.so.1, which exports only the private `_so_*` syscall
# wrappers. Those live in libsocket.so.1 and libnsl.so.1.
#
# Those two, and libnvpair, are joined in here rather than left as separate
# packages, for three reasons:
#
#  1. It matches what a real illumos root filesystem looks like. All of these
#     are in /lib or /usr/lib on any installed system, and every autoconf
#     script written for Solaris passes `-lsocket -lnsl -ldl` with no search
#     path of its own. Keeping them separate would mean teaching every
#     downstream package about a new buildInput that upstream has never heard
#     of.
#  2. `-lnsl` in particular is passed *unconditionally* by a lot of software
#     (gnutar's rmt client, openssl's Configure) and conditionally, on the
#     strength of a link test, by more. A link test that fails for want of a
#     -L flag silently selects the fallback path -- that is exactly how tcl
#     ended up compiling `compat/fake-rfc2553.c`.
#  3. libnsl.so.1's own DT_NEEDEDs are libmp.so.2 and libmd.so.1, and the
#     illumos link-editor requires a dependency's dependencies to be findable
#     on the link path. Joining libnsl without them would produce link failures
#     in every consumer.
#
# This is the same call netbsd/pkgs/libc.nix and freebsd/pkgs/libc make -- both
# join a good deal more than the literal libc.so, on the same "this is what the
# platform's base library set is" reasoning.
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
        libdl
        libsocket
        libnsl
        libmd
        libmp
        libnvpair
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
