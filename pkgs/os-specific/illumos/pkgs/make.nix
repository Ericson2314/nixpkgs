{
  lib,
  stdenv,

  filterSource,
  filterPatches,
  patchesRoot,
  version,

  gnumake,
  pkg-config,

  libtirpc,
}:

let
  path = "usr/src/cmd/make";
  manPath = "usr/src/man/man1/make.1";
in

stdenv.mkDerivation (finalAttrs: {
  pname = "make-illumos";
  inherit version;

  # dmake is the one program in the gate that its own makefiles cannot build,
  # because they are written in dmake's dialect and dmake is this program. The
  # gate answers that with `usr/src/cmd/make/Makefile.bootstrap`, a makefile in
  # the common subset of dialects that whatever make the build host ships can
  # read; see the `cmd/make: build on a non-illumos host` patch. Everything
  # this package needs therefore comes out of the gate, not out of a
  # third-party port of it.
  src = filterSource {
    inherit (finalAttrs) pname;
    inherit path;
    extraPaths = [ manPath ];
  };

  patches = filterPatches { } patchesRoot [ path ];

  postPatch = ''
    cd ${path}
  '';

  outputs = [
    "out"
    "man"
  ];

  strictDeps = true;

  nativeBuildInputs = [
    gnumake
    pkg-config
  ];

  # bin/pmake.cc calls host2netname()/netname2host(), which on a host whose
  # libc has no Secure RPC live in libtirpc.
  buildInputs = [ libtirpc ];

  # lib/vroot/report.cc passes a non-literal format string to fprintf(3C).
  hardeningDisable = [ "format" ];

  makeFlags = [
    "-f"
    "Makefile.bootstrap"
    "CXX=${stdenv.cc.targetPrefix}c++"
    "PREFIX=${placeholder "out"}"
  ];

  preBuild = ''
    makeFlagsArray+=(
      "CPPFLAGS=$(pkg-config --cflags libtirpc)"
      "LDFLAGS=$(pkg-config --libs-only-L libtirpc)"
    )
  '';

  postInstall = ''
    install -Dm444 ../../man/man1/make.1 $man/share/man/man1/make.1
    ln -s make.1 $man/share/man/man1/dmake.1
  '';

  meta = {
    description = "illumos make (dmake), built for the machine doing the building";
    homepage = "https://illumos.org/";
    license = lib.licenses.cddl;
    mainProgram = "make";
  };
})
