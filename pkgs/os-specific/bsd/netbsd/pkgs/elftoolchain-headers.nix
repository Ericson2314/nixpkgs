{
  lib,
  mkDerivation,
  bsdSetupHook,
  netbsdSetupHook,
  makeMinimal,
  install,
  statHook,
  m4,
  defaultMakeFlags,
}:

# `external/bsd/elftoolchain/common` exists only to install two headers, one of
# which -- `sys/elfdefinitions.h` -- is generated from `.m4` at build time.
# `libelf` and `libdwarf` both include it, so it has to be a package of its own
# rather than something either library can produce for itself.
mkDerivation {
  path = "external/bsd/elftoolchain/common";

  headersOnly = true;

  nativeBuildInputs = [
    bsdSetupHook
    netbsdSetupHook
    makeMinimal
    install
    statHook
    m4
  ];

  makeFlags = defaultMakeFlags ++ [ "TOOL_M4=m4" ];

  # `common/Makefile` installs `elfdefinitions.h` and recurses into `sys`, which
  # installs a second, different `elfdefinitions.h` under `INCSDIR=/usr/include/
  # sys`. `netbsdSetupHook` forces `INCSDIR` on the make command line, where it
  # overrides both, so the two headers land on top of each other and only the
  # `sys` one survives. Place them by hand instead; the build has already
  # generated the `sys` one from `.m4` by this point.
  installPhase = ''
    includesPhase
    mkdir -p $out/include/sys
    install -m 444 ../dist/common/elfdefinitions.h $out/include/elfdefinitions.h
    install -m 444 sys/elfdefinitions.h $out/include/sys/elfdefinitions.h
  '';

  extraPaths = [ "external/bsd/elftoolchain/dist/common" ];

  meta.platforms = lib.platforms.netbsd;
}
