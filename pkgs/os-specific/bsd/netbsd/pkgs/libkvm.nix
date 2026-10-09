{
  lib,
  stdenvLibcMinimal,
  mkDerivation,
  bsdSetupHook,
  netbsdSetupHook,
  makeMinimal,
  install,
  tsort,
  lorder,
  mandoc,
  statHook,
}:

mkDerivation {
  path = "lib/libkvm";

  libcMinimal = true;

  outputs = [
    "out"
    "dev"
    "man"
  ];

  nativeBuildInputs = [
    bsdSetupHook
    netbsdSetupHook
    makeMinimal
    install
    tsort
    lorder
    mandoc
    statHook
  ];

  SHLIBINSTALLDIR = "$(out)/lib";

  # Hack around GCC's limits.h missing the include_next we want. See
  # https://gcc.gnu.org/legacy-ml/gcc/2003-10/msg01278.html
  NIX_CFLAGS_COMPILE_BEFORE = "-isystem ${stdenvLibcMinimal.cc.libc.dev}/include";

  # `libkvm` reads kernel data structures, so it compiles against the kernel
  # sources rather than just the installed headers -- hence `-I${NETBSDSRCDIR}/sys`
  # and `-D_KMEMUSER` in its Makefile.
  extraPaths = [
    "sys"
    "common"
  ];

  meta.platforms = lib.platforms.netbsd;
}
