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

    # `ld: bootxx_ffsv1.sym: error: PHDR segment not covered by LOAD segment`.
    # Upstream fixed this for `efiboot`; the other i386 booters share
    # `Makefile.booters`, which never got the same flags.
    ./booters-no-dynamic-linker.patch

    # `### bootxx_ext2fs size 8020 is larger than 7680`, and likewise for
    # `bootxx_ustarfs`. The primary bootstraps have a fixed sector budget that
    # GCC 15 overruns, so build them `-Oz` -- which is what NetBSD already does
    # for these same files under clang.
    ./bootxx-oz.patch
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
