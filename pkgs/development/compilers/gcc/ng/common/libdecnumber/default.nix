{
  lib,
  stdenv,
  gcc_meta,
  version,
  monorepoSrc ? null,
  runCommand,
}:
# The decimal-float library `gcc/` links (`gcc/Makefile.in:474`). Unlike
# `libcpp` it also wants a *build*-directory include, `-I../libdecnumber`
# (`:473`), for the generated `config.h` -- so both files are installed and the
# consumer is given a directory containing them.
stdenv.mkDerivation (finalAttrs: {
  pname = "libdecnumber";
  inherit version;

  src = runCommand "libdecnumber-src-${version}" { src = monorepoSrc; } ''
    runPhase unpackPhase

    mkdir -p "$out"
    cp -r include "$out"
    cp -r libdecnumber "$out"
    cp config.guess config.rpath config.sub install-sh mkinstalldirs depcomp compile missing move-if-change "$out"
  '';

  outputs = [ "out" ];

  enableParallelBuilding = true;
  strictDeps = true;

  sourceRoot = "${finalAttrs.src.name}/libdecnumber";

  preConfigure = ''
    mkdir ../../build
    cd ../../build
    configureScript=../$sourceRoot/configure
  '';

  # `decContext.h:54` includes "gstdint.h", which this component's configure
  # generates into its build directory. `-I../libdecnumber` in `gcc/` is what
  # finds it, so it crosses the boundary alongside `config.h` -- named, not
  # globbed, because a missing generated header shows up hundreds of lines
  # away in someone else's compile.
  installPhase = ''
    runHook preInstall

    test -f libdecnumber.a
    test -f config.h
    test -f gstdint.h

    install -Dm644 libdecnumber.a "$out/lib/libdecnumber.a"
    install -Dm644 config.h "$out/include/config.h"
    install -Dm644 gstdint.h "$out/include/gstdint.h"

    runHook postInstall
  '';

  passthru.isGNU = true;

  meta = gcc_meta // {
    homepage = "https://gcc.gnu.org/";
  };
})
