{
  stdenv,

  source,
  fetchpatch,

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

  patches = [
    (fetchpatch {
      name = "linux-support.patch";
      url = "https://github.com/illumos/illumos-gate/compare/${source.rev}...Ericson2314:illumos-gate:linux-dmake.diff";
      hash = "sha256-iTtLU5mMGuaQEs+wrdYT3XzJB3vv3dCPo2Ia7vB1MIk=";
      relative = dir;
      postFetch = ''
        sed -i $out -e 's_a//dev/null_/dev/null_'
      '';
    })
  ];

  postPatch = ''
    cp ${source}/usr/src/OPENSOLARIS.LICENSE COPYING
    mkdir -p man/man1
    cp ${source}/usr/src/man/man1/make.1 man/man1/make.1
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
