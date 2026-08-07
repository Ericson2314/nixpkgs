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

  crt,
  headers,
}:

mkDerivation {
  noLibc = true;
  path = "usr/src/lib/libc/amd64";
  pname = "libcMinimal-illumos";

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

  nativeBuildInputs = [
    illumosSetupHook
    make
    install
    #gencat
    cw
    # libc builds its archive as `ar q $@ \`lorder ... | tsort\``; tsort comes
    # from coreutils in stdenv, but lorder is illumos' own.
    lorder
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
    # The libc_pic.a rule runs `mcs -d -n .SUNW_ctf` to strip CTF from the
    # archive. CTF generation is disabled for the cross build, so there is
    # nothing to strip, and mcs itself is not packaged yet (it needs libelf).
    "MCS=:"
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
