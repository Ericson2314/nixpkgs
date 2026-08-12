{
  lib,
  mkDerivation,
  bsdSetupHook,
  netbsdSetupHook,
  makeMinimal,
  install,
  tsort,
  lorder,
  mandoc,
  statHook,
  m4,
  elftoolchain-headers,
  defaultMakeFlags,
}:

mkDerivation {
  path = "external/bsd/elftoolchain/lib/libelf";

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
    m4
  ];

  buildInputs = [ elftoolchain-headers ];

  SHLIBINSTALLDIR = "$(out)/lib";

  # Three of the sources -- `libelf_convert.c`, `libelf_fsize.c` and
  # `libelf_msize.c` -- are generated from `.m4` templates.
  makeFlags = defaultMakeFlags ++ [ "TOOL_M4=m4" ];

  # The library itself lives in the vendored elftoolchain `dist` tree; the
  # NetBSD-side directory is only a Makefile pointing at it.
  extraPaths = [
    "external/bsd/elftoolchain/common"
    "external/bsd/elftoolchain/dist/common"
    "external/bsd/elftoolchain/dist/libelf"
  ];

  meta.platforms = lib.platforms.netbsd;
}
