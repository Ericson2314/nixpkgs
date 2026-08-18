{
  lib,
  buildPackages,
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
  nss-files,
  libresolv,
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
        # The "files" name-service backend. Unlike everything else here this is
        # not linked against -- libc dlopen()s it by name, "nss_files.so.1",
        # with no path (NSS_DLOPEN_FORMAT in lib/libc/port/gen/nss_deffinder.c).
        # A pathless dlopen searches the runpath of the calling object and of
        # the executable, and every illumos binary already has this composite's
        # lib directory on its runpath -- so putting the backend here is what
        # makes it findable at all. It also matches the real system layout,
        # where /lib holds libc.so.1 and nss_files.so.1 side by side.
        #
        # Without it `getpwnam("root")` fails and nothing can turn a name into
        # a uid: no login, no getent, and no sshd -- openssh is built here with
        # withPAM off, so it authenticates against /etc/shadow itself rather
        # than through a PAM stack, and depends on this backend directly.
        nss-files

        # The BIND resolver. libc and libnsl between them give you
        # `gethostbyname` through the name-service switch, but not the
        # `res_*` entry points underneath it, and krb5 needs those. Its
        # `AC_SEARCH_LIBS(res_nsearch, resolv)` is a link-time probe like the
        # ones described above, except that this one does *not* quietly pick a
        # fallback -- it stops the configure outright with "cannot find
        # res_nsearch or res_search" -- so curl loses GSSAPI unless -lresolv is
        # findable here.
        libresolv
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

  ''
  # illumos names the 64-bit runtime linker directory "64", and on x86 that is
  # a symlink to "amd64" -- which is where rtld installs and what its SONAME
  # and every PT_INTERP say. Provide the alias the wrapper expects.
  + ''
    if [ ! -e "$out/lib/64" ]; then
      ln -s amd64 "$out/lib/64"
    fi

  ''
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
  # dlerror, dladdr, dlinfo), so nothing needs libdl.so.1 at run time. glibc
  # did the same when it emptied libdl in 2.34.
  #
  # It must NOT be done by pointing libdl.so at libc.so.1, though, which is the
  # obvious spelling and is what stood here. `-ldl` then records DT_NEEDED
  # **libc.so.1**, at the position -ldl occupied on the link line -- which for
  # anything using pkg-config is early, ahead of the -lstdc++ -lgcc_s that
  # gcc's own specs append at the end. illumos libc.so.1 exports the C++ unwind
  # ABI itself (_Unwind_RaiseException, _Unwind_Resume, _Unwind_GetIP, ... --
  # the Solaris unwinder in lib/libc/port/unwind), so ld.so.1's breadth-first
  # search then binds libstdc++'s __cxa_throw to *libc's* unwinder rather than
  # libgcc_s's. That unwinder does not do gcc's PT_GNU_EH_FRAME/dl_iterate_phdr
  # FDE lookup, finds no handler for anything, and every C++ throw in the
  # process calls std::terminate:
  #
  #     terminate called after throwing an instance of 'nix::BadURL'
  #     terminate called recursively
  #
  # Not hypothetical: that is exactly why `svc:/site/nix-daemon:default` crash
  # looped. bdw-gc.pc says `Libs: -lgc -lpthread -lrt -ldl`, so libnixexpr and
  # every nix binary got libc.so.1 into DT_NEEDED slot 6, ahead of libgcc_s,
  # and nix could not complete a single throw. -lpthread and -lrt do not do
  # this, because they resolve to real libpthread.so.1/librt.so.1 SONAMEs and
  # so leave libc at depth 2 of the graph, behind libgcc_s.
  #
  # So: an empty shared object with SONAME libdl.so.1 that merely NEEDs
  # libc.so.1. `-ldl` resolves, libc stays at depth 2 where it belongs, and
  # there is no filter -- which is the other half of why the stock
  # libdl-illumos filter cannot be used here either. Its DT_FILTER is a path to
  # ld.so.1 that does not match this store's PT_INTERP, so ld.so.1 maps a
  # second copy of itself as an ordinary object ("loading after relocation has
  # started: interposition request (DF_1_INTERPOSE) ignored"), libc hands its
  # interface table to the copy that is not driving the process, and the
  # program dies with SIGSEGV before main(). Verified in a booted guest: a
  # program linked against the real libdl.so.1 filter dies before printing its
  # first line.
  #
  # crti.o/crtn.o are there only to give ld an input file -- it refuses a link
  # with none ("ld: fatal: no files on input command line"). They contribute no
  # code beyond the empty .init/.fini frames.
  + ''
    "$illumosLd/bin/ld-unwrapped" -64 -G \
      -h libdl.so.1 -N libc.so.1 \
      -o "$TMPDIR/libdl.so.1" \
      "$out/lib/crti.o" "$out/lib/crtn.o"

    rm -f "$out/lib/libdl.so.1" "$out/lib/libdl.so"
    cp "$TMPDIR/libdl.so.1" "$out/lib/libdl.so.1"
    ln -s libdl.so.1 "$out/lib/libdl.so"

    fixupPhase
  '';

  # Used by the postBuild above. Passed as a plain env var rather than through
  # nativeBuildInputs, since this is a symlinkJoin and nothing else here wants
  # a linker on PATH.
  illumosLd = buildPackages.illumos.ld;

  # illumos' threads are POSIX threads, and they live in libc.so.1 itself --
  # libpthread.so.1 is joined in above only as a filter, so that an
  # unconditional `-lpthread` resolves. `libgcc` and `libstdc++` have to be
  # configured for the same threading model as each other, so rather than have
  # each guess, they take it from the libc they are built against.
  #
  # Leaving this out is silent and expensive: `libgcc` defaults to "single",
  # `libstdcxx` copies `gthr-single.h` to `gthr-default.h`,
  # `GLIBCXX_CHECK_GTHREADS` then finds no gthreads and `c++config.h` comes out
  # with `_GLIBCXX_HAS_GTHREADS` undefined -- so `<mutex>` compiles away,
  # `std::mutex` does not exist, and every C++ consumer that wants threads
  # fails far downstream. boost is the one that finds it first, with
  # "Threading support unavaliable: it has been explicitly disabled with
  # BOOST_DISABLE_THREADS", which takes nix (and hence the whole system path)
  # with it.
  passthru.threadModel = "posix";

  meta.platforms = lib.platforms.illumos;
}
