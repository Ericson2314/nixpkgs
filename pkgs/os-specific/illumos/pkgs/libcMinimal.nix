{
  lib,
  stdenv,
  stdenvNoLibc,
  mkDerivation,
  buildPackages,

  illumosSetupHook,
  make,
  install,
  flex,
  byacc,
  #gencat,
  cw,
  lorder,
  ld-native,
  genoffsets,
  ctfstabs,
  ctfconvert,
  nawk,

  crt,
  headers,
}:

mkDerivation {
  noLibc = true;
  path = "usr/src/lib/libc/amd64";
  pname = "libcMinimal-illumos";

  # No "man": the man pages live in usr/src/man, not in the libc build, so
  # nothing would ever be installed into that output.
  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
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

  nativeBuildInputs = [
    illumosSetupHook
    make
    install
    #gencat
    cw
    # libc builds its archive as `ar q $@ \`lorder ... | tsort\``; tsort comes
    # from coreutils in stdenv, but lorder is illumos' own.
    lorder
    # port/gen/new_list.c is generated with nawk.
    nawk
    # libc.so.1 is linked through illumos' own ld: port/mapfile-vers is
    # `$mapfile_version 2`, which GNU ld cannot parse.
    ld-native
    # $(OFFSETS_CREATE) = genoffsets -s ctfstabs -r ctfconvert cw ... ; it
    # generates commpage/cp_offsets.h from offsets.in.
    genoffsets
    ctfstabs
    ctfconvert
    # illumos' own arch(1)/mach(1) report "i386" on x86, not "x86_64".
    (buildPackages.writeShellScriptBin "arch" "echo i386")
    (buildPackages.writeShellScriptBin "mach" "echo i386")
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
    # The libc_pic.a rule runs `mcs -d -n .SUNW_ctf` to strip CTF from the
    # archive. CTF generation is disabled for the cross build, so there is
    # nothing to strip, and mcs itself is not packaged yet (it needs libelf).
    "MCS=:"
    # Makefile.master leaves POST_PROCESS_O empty and Makefile.lib appends
    # "; $(CTFCONVERT_POST)" to it, so the recipe line starts with a bare `;`
    # and the shell rejects it. We have no CTF tools here anyway, so override
    # the whole macro rather than patching the append.
    "POST_PROCESS_O=:"
    # Same for the shared-library side: Makefile.lib appends
    # "; $(CTFMERGE_POST)" to an empty POST_PROCESS_SO.
    "POST_PROCESS_SO=:"
    # LDFLAGS.native is $(LDASSERTS) $(BDIRECT) -- Solaris ld options, which
    # GNU ld rejects when linking the native genassym helper. Clear just that,
    # not BDIRECT itself: DYNFLAGS also uses $(BDIRECT), and the libc.so.1 link
    # runs under illumos ld with -zguidance -zfatal-warnings, which turns a
    # missing -Bdirect into a hard error.
    "LDFLAGS.native="
    # genassym runs on the build machine but reports the *target*'s struct
    # offsets, so it is compiled by the host compiler against illumos headers.
    # Makefile.master defaults CPPFLAGS.native to -I/usr/include, which is not
    # where those headers live here.
    "CPPFLAGS.native=-I${headers}/include"
    # The installed headers must be searched *before* the -I flags individual
    # rules add, not after. Makefile.targ's regex rule adds
    # -I$(LIBCBASE)/../port/regex, and libc keeps a private regex.h there which
    # does not define REG_ESPACE and friends; a native build gets the public
    # <regex.h> first because $(COMPILE.c) already carries -I$(SRC)/head.
    # Arriving via -isystem (as buildInputs do) is too late in the search order.
    # CPPFLAGS.first is placed ahead of everything else in CPPFLAGS.
    "CPPFLAGS.first=-I${headers}/include"
    # illumos' MACH/MACH64 are not uname processor strings: on x86 they are
    # "i386" and "amd64". Source lookups depend on this -- Makefile.targ finds
    # the complex-arithmetic sources via $(LIBCBASE)/../$(MACH)/fp/%.c, which
    # is lib/libc/i386/fp. Passing MACH=x86_64 sends it to a directory that
    # does not exist.
    #
    # TARGET_ARCH is deliberately not overridden: lib/libc/amd64/Makefile sets
    # it to "amd64" itself, and a command-line macro would clobber that.
    "MACH=i386"
    "MACH64=amd64"

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

    # libc's BUILD.SO invokes $(LD) directly rather than the compiler driver,
    # and the mapfile it passes (-Wl,-M port/mapfile-vers) is version 2, which
    # only illumos' link-editor understands.
    #
    # This must name the *build-platform* ld explicitly. Splicing only rewrites
    # nativeBuildInputs, not string interpolation, so a bare `${ld-native}`
    # would pull in the target-platform build -- whose stdenv needs the very
    # libc we are building, giving infinite recursion.
    #
    # It is wrapped to clear SGS_SUPPORT: dmake sets that for .KEEP_STATE so
    # the link-editor dlopen()s libmakestate.so.1 to record dependencies. We
    # have no such support library, and ld's dlopen uses illumos-only mode
    # flags that glibc rejects outright ("invalid mode parameter").
    "LD=${
      buildPackages.writeShellScript "illumos-ld" ''
        unset SGS_SUPPORT SGS_SUPPORT_32 SGS_SUPPORT_64
        exec ${buildPackages.illumos.ld-native}/bin/ld "$@"
      ''
    }"
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
