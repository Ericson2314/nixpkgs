{
  lib,
  stdenv,
  gcc_meta,
  version,
  monorepoSrc ? null,
  runCommand,
  buildGccPackages,
}:
# GCC's preprocessor library. `gcc/` links `../libcpp/libcpp.a` and includes
# `$(srcdir)/../libcpp/include` (`gcc/Makefile.in:450-451`), so what it needs
# from here is the archive; the headers it takes from the source tree.
#
# It is a package because the `gcc` component is built on its own, without
# GCC's top level -- the top level is a distro layer and this package set is
# already the distro. Everything the top level would have built as a sibling is
# a derivation instead.
stdenv.mkDerivation (finalAttrs: {
  pname = "libcpp";
  inherit version;

  # LIBCPP REACHES INTO THE COMPILER'S BACK-END SOURCES, AND THIS SOURCE COPY IS
  # THE BOUNDARY VIOLATION MADE VISIBLE BY BUILDING THE COMPONENT ALONE.
  #
  # `libcpp/lex.cc:397` is `#include "../gcc/config/i386/cpuid.h"` -- a relative,
  # quoted include out of the preprocessor library into one back end's
  # directory, for the SSE-accelerated lexer. It is a fact about the machine
  # libcpp is being COMPILED for, so it is not target-dependence, but it does
  # mean `libcpp` cannot be built without part of `gcc/`. Hence the
  # `cp -r gcc/config` below.
  #
  # Copied rather than papered over: the include is real, and the fix is
  # upstream (a host-capability header of libcpp's own), not here.
  src = runCommand "libcpp-src-${version}" { src = monorepoSrc; } ''
    runPhase unpackPhase

    mkdir -p "$out/gcc"
    cp gcc/BASE-VER "$out/gcc"
    cp gcc/DATESTAMP "$out/gcc"

    cp -r include "$out"
    cp -r libcpp "$out"
    mkdir -p "$out/gcc"
    cp -r gcc/config "$out/gcc"

    cp config.guess config.rpath config.sub install-sh mkinstalldirs depcomp compile missing move-if-change "$out"
  '';

  outputs = [ "out" ];

  enableParallelBuilding = true;
  strictDeps = true;

  # `cpp_error (pfile, CPP_DL_ERROR, paste_op_error_msg)` -- the diagnostic
  # string is a variable, so `-Wformat-security` refuses it and `-Werror` stops
  # the build. The monolithic `gcc` derivation disables the same hardening flag
  # for the same reason, naming libcpp in its comment; now that libcpp is built
  # on its own the flag has to be here too.
  hardeningDisable = [ "format" ];

  sourceRoot = "${finalAttrs.src.name}/libcpp";

  depsBuildBuild = [ buildGccPackages.libiberty ];

  preConfigure = ''
    mkdir ../../build
    cd ../../build
    configureScript=../$sourceRoot/configure
  '';

  # There is no `install` target -- this library has never been installed by
  # anything, only linked out of a sibling build directory. Name the two files
  # the consumer asked for rather than globbing: an empty `lib` would look like
  # a successful build.
  installPhase = ''
    runHook preInstall

    test -f libcpp.a
    test -f config.h

    install -Dm644 libcpp.a "$out/lib/libcpp.a"
    install -Dm644 config.h "$out/include/libcpp-config.h"

    runHook postInstall
  '';

  passthru.isGNU = true;

  meta = gcc_meta // {
    homepage = "https://gcc.gnu.org/";
  };
})
