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
  '';

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
    # -Bdirect and the -z assertions are Solaris ld options; GNU ld rejects
    # them outright when linking the native genassym helper.
    "BDIRECT="
    "LDASSERTS="
    # genassym runs on the build machine but reports the *target*'s struct
    # offsets, so it is compiled by the host compiler against illumos headers.
    # Makefile.master defaults CPPFLAGS.native to -I/usr/include, which is not
    # where those headers live here.
    "CPPFLAGS.native=-I${headers}/include"
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
  ];

  # The `install` target lives in usr/src/lib/libc/Makefile, which drives the
  # per-ISA subdirectories; we build usr/src/lib/libc/amd64 directly, and it
  # only has `all`. So install the archive by hand.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libc_pic.a "$out/lib/"

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
