{
  stdenv,

  source,

  pkg-config,
  cmake,
  ninja,
  rpcsvc-proto,

  libbsd,
  libtirpc,
}:

let
  dir = "usr/src/cmd/make";
in

stdenv.mkDerivation {
  pname = "make-illumos";
  version = builtins.substring 0 7 source.rev;

  src = source + "/" + dir;

  outputs = [
    "out"
    "man"
  ];

  # dmake is not built by the illumos build system here, but by a CMake port of
  # it (the illumos-gate `linux-dmake` branch), so this one keeps a single
  # whole-tree patch rather than going through `filterPatches`.
  patches = [ ./linux-dmake.patch ];

  postPatch = ''
    cp ${source}/usr/src/OPENSOLARIS.LICENSE COPYING
    mkdir -p man/man1
    cp ${source}/usr/src/man/man1/make.1 man/man1/make.1

    # The dmake port asks for `cmake_minimum_required(VERSION 2.8)`, and CMake
    # has since removed compatibility with anything below 3.5.
    substituteInPlace CMakeLists.txt \
      --replace-fail 'cmake_minimum_required(VERSION 2.8)' \
                     'cmake_minimum_required(VERSION 3.5)'
  '';

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    rpcsvc-proto
  ];

  buildInputs = [
    libbsd
    libtirpc
  ];

  hardeningDisable = [ "format" ];
}
