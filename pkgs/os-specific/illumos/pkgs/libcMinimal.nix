{
  lib,
  stdenv,
  stdenvNoLibc,
  mkDerivation,
  buildPackages,

  fetchpatch,
  source,

  illumosSetupHook,
  make,
  install,
  flex,
  byacc,
  #gencat,
  cw,

  crt,
  headers,
}:

mkDerivation {
  noLibc = true;
  path = "usr/src/lib/libc/amd64";
  pname = "libcMinimal-openbsd";

  outputs = [
    "out"
    "dev"
    "man"
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
  ];

  patches = [
    (fetchpatch {
      name = "linux-support.patch";
      url = "https://github.com/illumos/illumos-gate/compare/${source.rev}...Ericson2314:illumos-gate:libc-hack.diff";
      hash = "sha256-T0Cyy1Q1NPqocQA77bNpDnRp8PjuiV/9Bf6rg84aTTc=";
    })
    ../patches/no-64-special-tools.patch
    ../patches/clang-skip-flags.patch
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    install
    #gencat
    cw
    (buildPackages.writeShellScriptBin "arch" "echo ${stdenv.buildPlatform.uname.processor}")
    (buildPackages.writeShellScriptBin "mach" "echo ${stdenv.hostPlatform.uname.processor}")
  ];

  buildInputs = [
    headers
    crt
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  makeFlags = [
    "COMPILER_VERSION=clang"
    "LIBC_TAGS=no"
    "HOST_ARCH=${stdenv.buildPlatform.uname.processor}"
    "TARGET_ARCH=${stdenv.hostPlatform.uname.processor}"
    "HOST_MACH=${stdenv.buildPlatform.uname.processor}"
    "TARGET_MACH=${stdenv.hostPlatform.uname.processor}"
    "MACH=$(TARGET_MACH)"
  ];

  postInstall = ''
    pushd ${headers}
    find include -type d -exec mkdir -p "$dev/{}" ';'
    find include '(' -type f -o -type l ')' -exec cp -pr "{}" "$dev/{}" ';'
    popd
    substituteInPlace "$dev/include/sys/time.h" --replace "defined (_LIBC)" "true"

    pushd ${crt}
    find lib -type d -exec mkdir -p "$out/{}" ';'
    find lib '(' -type f -o -type l ')' -exec cp -pr "{}" "$out/{}" ';'
    popd
  '';
}
