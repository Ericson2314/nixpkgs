{
  lib,
  mkDerivation,
  include,
  bsdSetupHook,
  netbsdSetupHook,
  makeMinimal,
  install,
  tsort,
  lorder,
  statHook,
  uudecode,
  config,
  genassym,
  defaultMakeFlags,
}:
{
  path = "sys";

  # Make the build ignore linker warnings
  prePatch = ''
    substituteInPlace sys/conf/Makefile.kern.inc \
      --replace "-Wa,--fatal-warnings" ""
  '';

  patches = [
    # multiple header dirs, see above
    ./sys-headers-incsdir.patch
  ];

  postPatch = ''
    substituteInPlace sys/arch/i386/stand/efiboot/Makefile.efiboot \
      --replace "-nocombreloc" "-z nocombreloc"
  ''
  +
    # multiple header dirs, see above
    include.postPatch;

  CONFIG = "GENERIC";

  propagatedBuildInputs = [ include ];
  nativeBuildInputs = [
    bsdSetupHook
    netbsdSetupHook
    makeMinimal
    install
    tsort
    lorder
    statHook
    uudecode
    config
    genassym
  ];

  postConfigure = ''
    pushd arch/$MACHINE/conf
    config $CONFIG
    popd
  ''
  # multiple header dirs, see above
  + include.postConfigure;

  makeFlags = defaultMakeFlags ++ [ "FIRMWAREDIR=$(out)/libdata/firmware" ];
  hardeningDisable = [ "pic" ];
  MKKMOD = "no";
  env.NIX_CFLAGS_COMPILE = toString [
    "-Wno-error=array-parameter"
    "-Wno-error=array-bounds"
    # `bitoff` in `common/lib/libc/gen/ptree.c` is only ever assigned and
    # incremented, never read. GCC 16 counts `+=` as a set rather than a use, so
    # it now warns, and `prekern` builds with `-Werror`.
    "-Wno-error=unused-but-set-variable"
    "-Wa,--no-warn"
  ];

  postBuild = ''
    make -C arch/$MACHINE/compile/$CONFIG $makeFlags
  '';

  postInstall = ''
    cp arch/$MACHINE/compile/$CONFIG/netbsd $out
  '';

  postIncludes = ''
    install $BSDSRCDIR/lib/libossaudio/soundcard.h $out/include/soundcard.h
  '';

  meta.platforms = lib.platforms.netbsd;
  extraPaths = [
    "common"
    "lib/libossaudio"
  ];
}
