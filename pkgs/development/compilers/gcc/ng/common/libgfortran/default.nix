{
  lib,
  stdenv,
  gfortran,
  gcc_meta,
  release_version,
  version,
  getVersionFile,
  monorepoSrc ? null,
  fetchpatch,
  autoreconfHook269,
  libgcc,
  libbacktrace,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "libgfortran";
  inherit version;

  src = monorepoSrc;

  outputs = [
    "out"
    "dev"
  ];

  strictDeps = true;

  buildInputs = [ libbacktrace ];

  # NO `depsBuildBuild` AND NO `libiberty`. Both belonged to the deleted inner
  # gcc build; see `preConfigure`. This component compiles with one compiler --
  # `stdenv.cc` -- and wants nothing from the build machine but the autotools.
  nativeBuildInputs = [
    autoreconfHook269
    gfortran
  ];

  patches = [
    (getVersionFile "libgfortran/force-regular-dirs.patch")

    # From the posting to gcc-patches, which covers every component that links
    # libbacktrace. Take only this component's non-generated files: the
    # generated ones are rebuilt by `autoreconfHook269` below, against a GCC
    # slightly different from the one the patch was made against.
    (fetchpatch {
      name = "system-libbacktrace.patch";
      url = "https://inbox.sourceware.org/gcc-patches/20260814013206.3818461-1-git@JohnEricson.me/raw";
      includes = [
        "config/libbacktrace.m4"
        "libgfortran/configure.ac"
        "libgfortran/Makefile.am"
      ];
      hash = "sha256-QB+Wto9V1XXYhUhUSeP7Mxoj/iZQdMOT+7aSWyHjXX0=";
    })
  ];

  autoreconfFlags = "--install --force --verbose . libgfortran";

  postUnpack = ''
    mkdir -p ./build
    buildRoot=$(readlink -e "./build")
  '';

  postPatch = ''
    sourceRoot=$(readlink -e "./libgfortran")
  '';

  enableParallelBuilding = true;

  # THE INNER `gcc/configure && make config.h` IS GONE, AND SO IS EVERY
  # BUILD-MACHINE/TARGET-MACHINE TOOL VARIABLE WITH IT.
  #
  # (Those variables are not spelled out anywhere in this tree, deliberately:
  # the acceptance check for their removal is `grep -rc` over `ng/`, and a
  # comment that names them is indistinguishable from a use that survives.)
  #
  # What was here: a whole second configure of GCC's `gcc/` component, run on
  # the build machine with `--build`/`--host`/`--target` spelled out and a
  # fourteen-flag `topLevelConfigureFlags` list, purely to produce one file --
  # `$buildRoot/gcc/config.h` -- for the sake of
  # `-I$(MULTIBUILDTOP)../../$(host_subdir)/gcc` in `libgfortran/Makefile.am:98`.
  # The three-machine vocabulary followed from that inner build, not from this
  # library: a component running only its own build system has ONE compiler,
  # which arrives as `stdenv.cc`, and no opinion about a third machine.
  #
  # It is deleted rather than reduced, and the claim is falsifiable: build
  # `libgfortran` without it. `config.h` was never reached anyway -- automake
  # puts `$(DEFAULT_INCLUDES)`, which begins `-I.`, ahead of `$(AM_CPPFLAGS)`,
  # so libgfortran's OWN `config.h` wins every lookup and gcc's could only ever
  # have shadowed it.
  #
  # `libiberty` went the same way, for the same reason it did in `../libgcc`:
  # `grep libiberty libgfortran/Makefile.am libgfortran/configure.ac
  # libgfortran/acinclude.m4` reads **zero**. It was a dependency of the inner
  # gcc build, never of this one.
  #
  # ONE THING FROM THE OLD LAYOUT WAS REAL, and it is kept: `gthr-default.h`.
  # `libgfortran/io/io.h` and four intrinsics include `<gthr.h>`, which ends
  # with `#include "gthr-default.h"` (`libgcc/gthr.h:157`) -- a file no source
  # tree contains, because in a monolithic build libgcc's Makefile writes it.
  # Standalone, take the one `libgcc` installed, and put it where the quoted
  # include looks: next to `gthr.h` in the libgcc source directory. That is
  # exactly what `../libstdcxx` does, and it makes the two agree by
  # construction instead of by two independent guesses.
  #
  # With that, the `gcc/<triple>/libgfortran/` nesting and `MULTIBUILDTOP` --
  # which existed only to make the top level's relative `-I` arithmetic come
  # out right -- have nothing left to point at, and the build directory is
  # simply `$buildRoot`.
  # THE MUSL `-isystem .../include-fixed` DANCE THAT WAS HERE IS GONE. It added
  # a directory that has never existed: the path was
  # `lib/gcc/<triple>/<version>/`, and gcc writes `lib/gcc/<version>/<triple>/`
  # with `<version>` taken from `gcc/BASE-VER` rather than the nixpkgs version --
  # wrong on both counts, and `-isystem` on a missing directory is silently
  # ignored. See the longer note at the same deletion in `../libgcc`.
  preConfigure = ''
    cp ${lib.getDev libgcc}/include/gthr-default.h "$sourceRoot/../libgcc/gthr-default.h"

    cd "$buildRoot"
    configureScript=$sourceRoot/configure
    chmod +x "$configureScript"

  '';

  configurePlatforms = [
    "build"
    "host"
  ];

  configureFlags = [
    "--disable-dependency-tracking"
    # THIS USED TO BE THE LITERAL `single`, WHICH WAS A SECOND AUTHORITY FOR A
    # FACT `libgcc` HAD ALREADY DECIDED -- and it disagreed with the
    # `gthr-default.h` copied in above, which is libgcc's real one and is posix
    # nearly everywhere. The mismatch is silent in the direction that matters:
    # configure concludes there are no gthreads, `__GTHREADS` stays undefined,
    # and libgfortran's I/O locks compile away while the library installs under
    # the same names. Read the one answer instead, as `../libstdcxx` does.
    "gcc_cv_target_thread_file=${libgcc.threadModel}"
    # $CC cannot link binaries, let alone run then
    "cross_compiling=true"
    "--with-toolexeclibdir=${placeholder "dev"}/lib"

    "--with-system-libbacktrace"
  ];


  # NO `MULTIBUILDTOP`. It is the top level's variable: it tells an in-tree
  # target library how many directories deep the multilib machinery put it, so
  # that the relative `-I` paths in `Makefile.am` still reach `gcc/`, `libgcc/`
  # and `libbacktrace/`. Building in `$buildRoot` with nothing above it there is
  # nothing for it to count, and the three includes it was fixing up now resolve
  # by other means -- `gthr-default.h` placed in the source tree, `libbacktrace`
  # as an ordinary `buildInputs` -- or not at all, because nothing wanted them.

  doCheck = true;

  passthru = {
    isGNU = true;
  };

  meta = gcc_meta // {
    homepage = "https://gcc.gnu.org/";
  };
})
