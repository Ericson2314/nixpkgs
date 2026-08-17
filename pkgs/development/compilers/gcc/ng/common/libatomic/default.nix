{
  lib,
  stdenv,
  gcc_meta,
  release_version,
  version,
  getVersionFile,
  monorepoSrc ? null,
  fetchpatch,
  autoreconfHook269,
  runCommand,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "libatomic";
  inherit version;

  src = runCommand "libatomic-src-${version}" { src = monorepoSrc; } (
    ''
      runPhase unpackPhase

      mkdir -p "$out/gcc"
      cp gcc/BASE-VER "$out/gcc"
      cp gcc/DATESTAMP "$out/gcc"

      cp -r libatomic "$out"

      cp -r config "$out"
      cp -r multilib.am "$out"
      cp -r libtool.m4 "$out"

      cp config.guess "$out"
      cp config.rpath "$out"
      cp config.sub "$out"
      cp config-ml.in "$out"
      cp ltmain.sh "$out"
      cp install-sh "$out"
      cp mkinstalldirs "$out"

    ''
    # `MD5SUMS` exists only in release tarballs, not in a VCS checkout.
    + ''
      if [[ -f MD5SUMS ]]; then cp MD5SUMS "$out"; fi
    ''
  );

  patches = [
    # THE `custom-threading-model` BACKPORT IS GONE: it is an ancestor of the
    # pinned rev. Measured, the way the seven in `../gcc` and the four in
    # `../libgcc` were:
    #
    #     git merge-base --is-ancestor e5d853bbe9b0 1167d3f15f7   -> true
    #
    # Left in place it stopped the build with "Reversed (or previously applied)
    # patch detected ... Skipping patch ... 2 out of 2 hunks ignored", which is
    # the GOOD failure -- `patch` refused and exited non-zero. A fuzzier hunk
    # would have applied something twice in silence.
    # AND SO IS `libatomic/gthr-include.patch`, FOR THE REASON ITS OWN HEADER
    # GIVES: "This change was upstreamed in e5d853bbe9b0... but this file was
    # slightly different in GCC 15, so we are patching it manually." That commit
    # is an ancestor of the pinned rev, so the hand-application is redundant --
    # measured directly on the source: `libatomic/aclocal.m4:1194` already reads
    # `m4_include([../config/gthr.m4])`, which is the whole of what the patch
    # added.
    #
    # It also patched a GENERATED file. `autoreconfHook269` below regenerates
    # `aclocal.m4`, so even when it applied it was editing something that was
    # about to be overwritten -- the same trap as the `libgcc/configure` hunk
    # excluded from `regular-libdir-includedir` in `../libgcc`.
  ];

  postUnpack = ''
    mkdir -p ./build
    buildRoot=$(readlink -e "./build")
  '';

  preAutoreconf = ''
    sourceRoot=$(readlink -e "./libatomic")
    cd $sourceRoot
  '';

  enableParallelBuilding = true;

  nativeBuildInputs = [
    autoreconfHook269
  ];

  configurePlatforms = [
    "build"
    "host"
  ];
  # `CFLAGS` IS REQUIRED BY THIS COMPONENT, AND IT SAYS SO BY NAME.
  #
  # `libatomic/configure.ac:139` is a hard `AC_MSG_ERROR([CFLAGS must be set.])`,
  # and the comment above it explains why it cannot be left to autoconf:
  # libatomic needs `-fno-link-libatomic` in `CFLAGS` while `AC_PROG_CC` runs
  # its conftests, and `AC_PROG_CC` would otherwise default `CFLAGS` to `-g -O2`
  # AFTER that point, leaving nowhere to inject it. So it refuses to guess.
  #
  # In a top-level build `CFLAGS_FOR_TARGET` supplies this. Standalone the
  # caller does, and this package set is the caller -- the same shape as
  # `itoolsdir` in `../gcc` and `bindir`/`datadir` in `../fixincludes`. The
  # value is exactly what `AC_PROG_CC` would have defaulted to, which is what
  # the upstream comment describes as the thing being replaced; nixpkgs puts its
  # own flags in `NIX_CFLAGS_COMPILE`, so `CFLAGS` is free to carry this.
  env.CFLAGS = "-g -O2";


  configureFlags = [
    "--disable-dependency-tracking"
    "cross_compiling=true"
    "--disable-multilib"
  ];

  preConfigure = ''
    cd "$buildRoot"
    configureScript=$sourceRoot/configure
  '';

  doCheck = true;

  passthru = {
    isGNU = true;
  };

  meta = gcc_meta // {
    homepage = "https://gcc.gnu.org/";
  };
})
