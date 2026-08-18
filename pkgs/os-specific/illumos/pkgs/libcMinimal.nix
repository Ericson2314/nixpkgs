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
  ctfmerge,
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
    # turns lib/libc/i386/offsets.in into assym.h. genoffsets compiles the
    # #include lines from offsets.in into an object, runs ctfconvert over its
    # DWARF, and lets ctfstabs read the struct layouts back out of the CTF --
    # so the offsets that libc's assembly uses come from the *target*
    # compiler's own idea of the layout rather than from a hand-written list.
    genoffsets
    ctfstabs
    # Every PIC object gets a CTF section (Makefile.lib:208), and
    # libc.so.1 gets them all merged into one (Makefile.lib:209).
    ctfconvert
    ctfmerge
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
  ''
  # port/gen sources include their own private headers with angle brackets
  # (e.g. <getxby_door.h>), and we compile them from the amd64 directory, so
  # the source's own directory is not on the search path.
  + ''
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -I$SRC/lib/libc/port/gen"
  ''
  # A few libc sources include <cp_defs.h> from the commpage. That header is
  # self-contained (it pulls only <sys/types.h>); the generated cp_offsets.h
  # is needed solely by the commpage assembly, which we do not build. So the
  # include path alone suffices -- this is what COMMPAGE_CPPFLAGS would set.
  + ''
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -I$SRC/lib/commpage/common"
  ''
  # common/crypto/chacha/chacha.h, compiled into libc via CHACHAOBJS.
  + ''
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
    # mkDerivation's `libMakeFlags` already pass MCS=: and LDFLAGS.native=, and
    # set POST_PROCESS_O/POST_PROCESS_SO to `:` because most libraries here are
    # built without CTF. libc is the exception, so override just those two.
    #
    # Makefile.master:983 leaves POST_PROCESS_O empty and Makefile.lib:191
    # appends "; $(CTFCONVERT_POST)" to it, so the expanded recipe line starts
    # with a bare `;`, which the shell rejects. Restate the macro as just the
    # hook, dropping the leading separator. It has to stay a *reference* rather
    # than being resolved here: CTFCONVERT_POST is a target-conditional macro
    # (Makefile.lib:208 sets it to $(CTFCONVERT_O) for $(PICS) and leaves it
    # `:` elsewhere), so it must be expanded in the context of each target.
    #
    # This is what turns CTF back on: every pics/*.o then gets ctfconvert run
    # over the DWARF that $(CTF_FLAGS) asked for (amd64/Makefile:1046 adds
    # -g -gdwarf-4 -gstrict-dwarf to CFLAGS64).
    "POST_PROCESS_O=$(CTFCONVERT_POST)"
    # Likewise for the shared library, where CTFMERGE_POST is
    # $(CTFMERGE_LIB) = ctfmerge -t -f -L VERSION -o libc.so.1 $(PICS):
    # the per-object containers are merged into one .SUNW_ctf section with
    # duplicate types coalesced.
    #
    # POST_PROCESS_SO is not empty upstream -- Makefile.master:987 also runs
    # $(STRIP_STABS) and $(ELFSIGN_OBJECT). Both are dropped deliberately.
    # $(STRIP) here is GNU strip from the cross toolchain, which rewrites
    # rather than edits in place (see the STRIP_STABS note in unix.nix), and
    # there is no signing key to elfsign with.
    "POST_PROCESS_SO=$(CTFMERGE_POST)"
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
  ''
  # `headers` is a symlinkJoin, so copy with -L to get real files rather than
  # symlinks back into the store -- otherwise chmod and substituteInPlace
  # below follow them into read-only store paths and fail with EPERM.
  + ''
    find include '(' -type f -o -type l ')' -exec cp -pLr "{}" "$dev/{}" ';'
    popd
    chmod -R u+w "$dev/include"

    pushd ${crt}
    find lib -type d -exec mkdir -p "$out/{}" ';'
    find lib '(' -type f -o -type l ')' -exec cp -pr "{}" "$out/{}" ';'
    popd
  '';
}
