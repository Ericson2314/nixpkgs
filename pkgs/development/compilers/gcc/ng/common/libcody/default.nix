{
  lib,
  stdenv,
  gcc_meta,
  version,
  monorepoSrc ? null,
  runCommand,
}:
# The C++ modules mapper library `gcc/` links (`gcc/Makefile.in:453-454`);
# headers come from the source tree, so only the archive crosses the boundary.
stdenv.mkDerivation (finalAttrs: {
  pname = "libcody";
  inherit version;

  src = runCommand "libcody-src-${version}" { src = monorepoSrc; } ''
    runPhase unpackPhase

    mkdir -p "$out"
    cp -r libcody "$out"
    cp config.guess config.rpath config.sub install-sh mkinstalldirs depcomp compile missing move-if-change "$out"
  '';

  outputs = [ "out" ];

  enableParallelBuilding = true;
  strictDeps = true;

  sourceRoot = "${finalAttrs.src.name}/libcody";

  preConfigure = ''
    mkdir ../../build
    cd ../../build
    configureScript=../$sourceRoot/configure
  '';

  installPhase = ''
    runHook preInstall

    test -f libcody.a
    test -f config.h

    install -Dm644 libcody.a "$out/lib/libcody.a"
    install -Dm644 config.h "$out/include/config.h"

    runHook postInstall
  '';

  passthru.isGNU = true;

  meta = gcc_meta // {
    homepage = "https://gcc.gnu.org/";
  };
})
