{
  lib,
  mkDerivation,
  bsdSetupHook,
  netbsdSetupHook,
  makeMinimal,
  install,
  mandoc,
  groff,
  nbperf,
  compatIfNeeded,
  defaultMakeFlags,
  libterminfo,
}:

mkDerivation {
  path = "tools/tic";
  HOSTPROG = "tic";
  buildInputs = compatIfNeeded;
  nativeBuildInputs = [
    bsdSetupHook
    netbsdSetupHook
    makeMinimal
    install
    mandoc
    groff
    nbperf
  ];
  makeFlags = defaultMakeFlags ++ [ "TOOLDIR=$(out)" ];
  # Like `compat`, this is one of NetBSD's own build tools -- `tools/tic`, built
  # as a `HOSTPROG` -- and not a NetBSD program at all. Its Makefiles invoke the
  # plain build compiler as `cc`, so on a NetBSD host it is both unnecessary and
  # unbuildable. Say so in `meta`, so that asking for it there is refused up
  # front rather than dying mid-build on `cc: command not found`.
  meta.platforms = lib.subtractLists lib.platforms.netbsd lib.platforms.unix;
  extraPaths = [
    libterminfo.path
    "usr.bin/tic"
    "tools/Makefile.host"
  ];
}
