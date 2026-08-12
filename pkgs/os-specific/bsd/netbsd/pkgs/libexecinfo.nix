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
  libelf,
  elftoolchain-headers,
  defaultMakeFlags,
}:

mkDerivation {
  path = "lib/libexecinfo";

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

  # `LIBDPLIBS+= elf ...` in the Makefile, for reading the symbol table.
  buildInputs = [
    libelf
    elftoolchain-headers
  ];

  SHLIBINSTALLDIR = "$(out)/lib";

  makeFlags = defaultMakeFlags ++ [ "LIBDO.elf=${libelf}/lib" ];

  meta.platforms = lib.platforms.netbsd;
}
