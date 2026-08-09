{
  lib,
  symlinkJoin,
  libcMinimal,
  libm,
  libpthread,
  librt,
  libssp_ns,
  rtld,
  libdl,
  libsocket,
  libnsl,
  libmd,
  libmp,
  libnvpair,
  libsec,
  libavl,
  libidmap,
  libuutil,
  version,
}:

# The composite "libc" that the rest of nixpkgs means when it says slibc --
# same shape as netbsd/pkgs/libc.nix and freebsd/pkgs/libc. libcMinimal is
# only the bootstrap piece; things like gcc's libquadmath expect -lm to be
# available from the platform libc as well.
#
# libc.so.1 already implements the threads and rt interfaces that NetBSD splits
# into librt; libpthread.so.1 and librt.so.1 are still included, but only as
# *filter* libraries on libc -- they carry no code of their own, and exist so
# that an unconditional -lpthread (gcc's libsanitizer passes one) or -lrt
# (cmake adds one for any non-Linux UNIX; zstd, libarchive and CPython all end
# up with it) resolves. libdl.so.1 is a filter for the same reason, on ld.so.1.
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
        librt
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
        # libsec and its dependencies. coreutils' gnulib compiles the illumos
        # arm of `file-has-acl.c` because <sys/acl.h> *declares* `acl_trivial`,
        # but its `AC_SEARCH_LIBS` only links `-lsec` if the library is already
        # findable -- so without this the probe silently fails and the link
        # dies on an undefined `acl_trivial`. Same reasoning as libsocket/libnsl
        # above: a link-time probe that cannot find its library does not fail,
        # it picks the fallback.
        libsec
        libavl
        libidmap
        libuutil
      ];

  postBuild = ''
    rm -rf "$out/nix-support"

    # illumos names the 64-bit runtime linker directory "64", and on x86 that is
    # a symlink to "amd64" -- which is where rtld installs and what its SONAME
    # and every PT_INTERP say. Provide the alias the wrapper expects.
    if [ ! -e "$out/lib/64" ]; then
      ln -s amd64 "$out/lib/64"
    fi

    # Point the *link-time* -ldl at libc.so.1 rather than at libdl.so.1.
    #
    # A workaround for our layout, not a fix to illumos, so: stock libdl.so.1
    # is a pure filter whose DT_FILTER is the string "/lib/amd64/ld.so.1" --
    # the dl* entry points live in the runtime linker. On a stock system that
    # string is also the path the kernel used for PT_INTERP, so when ld.so.1
    # processes the filter it recognises the name as itself. Here PT_INTERP is
    # a store path, the names do not match, and ld.so.1 maps a *second copy of
    # itself* as an ordinary object: "loading after relocation has started:
    # interposition request (DF_1_INTERPOSE) ignored". libc then hands its
    # interface table over through the `_ld_libc` filtee binding (ATEXIT,
    # TLS_MODADD, TLS_MODREM, TLS_STATMOD, THRINIT) to the copy that is *not*
    # driving the process, and the program dies with SIGSEGV before main().
    #
    # It is order-sensitive: a program linked `-ldl` crashes, the same program
    # linked `-lc -ldl` runs, because when libc relocates first its own filter
    # binding happens early enough to interpose. bash links `... -lnsl -ldl`,
    # so it always loses.
    #
    # libc.so.1 already exports the whole dl* family (dlopen, dlsym, dlclose,
    # dlerror, dladdr, dlinfo), so nothing needs libdl.so.1 at run time. Making
    # the linker-visible libdl.so resolve to libc.so.1 means `-ldl` records
    # DT_NEEDED libc.so.1 -- already in every closure -- so there is no filter,
    # no second linker and no ordering sensitivity. glibc did the same when it
    # emptied libdl in 2.34. libdl.so.1 stays for anything already linked
    # against it.
    ln -sfn libc.so.1 "$out/lib/libdl.so"

    fixupPhase
  '';

  meta.platforms = lib.platforms.illumos;
}
