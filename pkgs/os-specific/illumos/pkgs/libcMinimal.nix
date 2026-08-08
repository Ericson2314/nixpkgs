{
  lib,
  stdenv,
  stdenvNoLibc,
  mkDerivation,
  buildPackages,

  flex,
  byacc,
  #gencat,
  lorder,
  genoffsets,
  ctfstabs,
  ctfconvert,
  nawk,

  crt,
  headers,
}:

mkDerivation {
  noLibc = true;
  illumosLib = true;
  path = "usr/src/lib/libc/amd64";
  pname = "libcMinimal-illumos";

  # No "man": the man pages live in usr/src/man, not in the libc build, so
  # nothing would ever be installed into that output.
  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/libc"
    "usr/src/lib/commpage"

    # The commpage builds against the platform's own headers:
    # commpage/Makefile.shared.com adds -I$(SRC)/uts/i86pc for cp_main.o,
    # cp_subr.o and cp_offsets.h, all of which need <sys/comm_page.h>.
    "usr/src/uts/i86pc/sys"

    # libc's Makefile.targ builds the values-X*.o objects straight out of
    # lib/crt/common (rule at Makefile.targ:283).
    "usr/src/lib/crt"

    # libc compiles a fair amount of code from $(SRC)/common: atomic, bitext,
    # crypto/chacha, dtrace, secflags, unicode, util and xattr. It is only
    # ~6MB, so take the lot rather than tracking each subdirectory.
    "usr/src/common"

    # libc/inc/libc.h includes <libnvpair.h>, which is not part of the
    # installed header set; it ships with the libnvpair library itself.
    "usr/src/lib/libnvpair"
  ];

  extraNativeBuildInputs = [
    #gencat
    # libc builds its archive as `ar q $@ \`lorder ... | tsort\``; tsort comes
    # from coreutils in stdenv, but lorder is illumos' own.
    lorder
    # port/gen/new_list.c is generated with nawk.
    nawk
    # $(OFFSETS_CREATE) = genoffsets -s ctfstabs -r ctfconvert cw ... ; it
    # generates commpage/cp_offsets.h from offsets.in.
    genoffsets
    ctfstabs
    ctfconvert
  ];

  # genassym is compiled and then *run* during the build to emit assym.h, so it
  # needs a compiler targeting the build machine. This is what puts
  # $CC_FOR_BUILD in the environment, which Makefile.master's NATIVE* compilers
  # are derived from.
  depsBuildBuild = [ buildPackages.stdenv.cc ];

  buildInputs = [
    headers
    crt
  ];

  # lib/libc/amd64/Makefile:1194 sets STACKPROTECT = none for the whole of
  # libc, but the nixpkgs cc wrapper puts -fstack-protector-strong back, so it
  # has to be turned off here as well.
  #
  # It matters for more than code size. With the stack protector on, every
  # libc_pic.a member references __stack_chk_fail, which drags in ssp.o, which
  # needs gethrtime(), which drags in clock_timer.o -- and that object also
  # carries timer_create(), hence sigev_thread.o and with it pthreads, aio,
  # syslog and stdio. A static link that should extract 69 objects extracts
  # 309, and the ld.so.1 link then fails on some forty multiply-defined symbols
  # (read, write, malloc, printf, mutex_lock, assfail) that rtld defines itself.
  hardeningDisable = [ "stackprotector" ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  # $SRC is only known at build time (illumosSetupHook sets it), so this cannot
  # go in env.NIX_CFLAGS_COMPILE above.
  preBuild = ''
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -I$SRC/lib/libnvpair"
    # port/gen sources include their own private headers with angle brackets
    # (e.g. <getxby_door.h>), and we compile them from the amd64 directory, so
    # the source's own directory is not on the search path.
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -I$SRC/lib/libc/port/gen"
    # A few libc sources include <cp_defs.h> from the commpage. That header is
    # self-contained (it pulls only <sys/types.h>); the generated cp_offsets.h
    # is needed solely by the commpage assembly, which we do not build. So the
    # include path alone suffices -- this is what COMMPAGE_CPPFLAGS would set.
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -I$SRC/lib/commpage/common"
    # common/crypto/chacha/chacha.h, compiled into libc via CHACHAOBJS.
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -I$SRC/common/crypto/chacha"
  '';

  # Must be explicit. Including commpage/Makefile.shared.targ near the top of
  # lib/libc/amd64/Makefile introduces an explicit target (cp_offsets.h) long
  # before `all:`, which makes it dmake's default goal -- so a bare `make`
  # generates that one header and stops, reporting success. Upstream never
  # trips over this because the parent lib/libc/Makefile always passes a target.
  buildFlags = [ "all" ];

  makeFlags = [
    "COMPILER_VERSION=clang"
    "LIBC_TAGS=no"

    # genassym runs on the build machine but reports the *target*'s struct
    # offsets, so it is compiled by the host compiler against illumos headers.
    # Makefile.master defaults CPPFLAGS.native to -I/usr/include, which is not
    # where those headers live here.
    "CPPFLAGS.native=-I${headers}/include"

    # `all: $(LIBS) $(LIB_PIC)`, and LIBS is set to $(DYNLIB) by the *parent*
    # lib/libc/Makefile, which drives the per-ISA subdirectories. We build
    # amd64/ directly, where Makefile.lib leaves LIBS empty -- so ask for the
    # shared library explicitly.
    "LIBS=libc.so.1"

    # ALTPICS is $(TRACEOBJS), i.e. plockstat.o, generated by `dtrace -G` from
    # port/threads/plockstat.d. dtrace is not packaged (it would drag in
    # libdtrace and more), so drop it; port/threads/plockstat_stub.c supplies
    # the __dtrace_plockstat___* symbols as empty functions instead. libc.so.1
    # then reports nothing through the plockstat provider, and is otherwise
    # unchanged.
    "TRACEOBJS="
  ];

  # The `install` target lives in usr/src/lib/libc/Makefile, which drives the
  # per-ISA subdirectories; we build usr/src/lib/libc/amd64 directly, and it
  # only has `all`. So install the archive by hand.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libc_pic.a "$out/lib/"
    cp libc.so.1 "$out/lib/"
    ln -s libc.so.1 "$out/lib/libc.so"

    runHook postInstall
  '';

  postInstall = ''
    pushd ${headers}
    find include -type d -exec mkdir -p "$dev/{}" ';'
    # `headers` is a symlinkJoin, so copy with -L to get real files rather than
    # symlinks back into the store -- otherwise chmod and substituteInPlace
    # below follow them into read-only store paths and fail with EPERM.
    find include '(' -type f -o -type l ')' -exec cp -pLr "{}" "$dev/{}" ';'
    popd
    chmod -R u+w "$dev/include"

    pushd ${crt}
    find lib -type d -exec mkdir -p "$out/{}" ';'
    find lib '(' -type f -o -type l ')' -exec cp -pr "{}" "$out/{}" ';'
    popd
  '';
}
