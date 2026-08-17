{
  lib,
  stdenv,
  gcc_meta,
  release_version,
  version,
  monorepoSrc ? null,
  fetchpatch,
  langAda ? false,
  langC ? true,
  langCC ? true,
  langFortran ? false,
  langGo ? false,
  langJava ? false,
  langObjC ? true,
  langObjCpp ? true,
  langJit ? false,
  enablePlugin ? lib.systems.equals stdenv.hostPlatform stdenv.buildPlatform,
  buildPackages,
  isl,
  zlib,
  gmp,
  libmpc,
  mpfr,
  perl,
  texinfo,
  which,
  gettext,
  flex,
  bison,
  # Whether `monorepoSrc` is a VCS checkout rather than a release tarball. A
  # checkout lacks the generated sources (gengtype-lex.cc and friends) that a
  # tarball ships pre-built, so they have to be regenerated with flex and bison.
  fromVCS ? false,
  getVersionFile,
  buildGccPackages,
  libbacktrace,
  autoreconfHook269,
  bintools,
  enableShared ? stdenv.hostPlatform.hasSharedLibraries,
  # NO `enableTargetShared`. It used to be
  #
  #   enableTargetShared ? stdenv.targetPlatform.hasSharedLibraries
  #                        && !stdenv.targetPlatform.isCygwin
  #
  # feeding `--enable-shared`/`--disable-shared`, which decides whether the
  # driver's specs emit `-lgcc_s`. That is a per-*target* fact, and a compiler
  # serving many targets cannot answer it once at configure time: whichever
  # answer it froze would be wrong for every target that disagrees, silently,
  # in the link line.
  #
  # It was also the last `targetPlatform` reference in this file, and it was
  # invisible until `mt-compare.nix` grew a Cygwin arm -- the aarch64 and NetBSD
  # arms both take the same branch of that condition, so two arms could not see
  # it. Three could.
  #
  # The answer belongs where the rest of the per-target link behaviour now
  # lives: `target-specs/configure --with-shared-libgcc=yes|no`, which writes it
  # into that one target's spec file, probed against that target's actual
  # toolchain.
  # Back ends this compiler serves, as a list of config triples, passed to
  # `gcc/configure` as `--enable-backends`.
  #
  # `null` -- THE DEFAULT -- MEANS NIXPKGS NAMES NOTHING AT ALL, and that is
  # the whole point of the argument. `gcc/configure` defaults the flag to the
  # tree's own `gcc/default-backends`, so the compiler serves every back end the
  # source ships and the packaging is not an authority for the list.
  #
  # The previous shape read `gcc/default-backends` out of `$src` in
  # `preConfigure` and passed the 47 triples back in. That removed the
  # `targetPlatform` reference but left nixpkgs holding the list, so the store
  # path depended on a value the packaging computed -- target-dependence
  # returning by the front door. The fix went into `gcc/configure`
  # (`configure.ac`, the `no | ""` arm of the `enable_backends` case).
  #
  # A non-null value is still accepted, for exactly one purpose: the `differ`
  # arm of `mt-compare.nix`, which must be able to produce a deliberately
  # different compiler so that the instrument can be shown capable of failing.
  #
  # `--enable-targets` IS NOT USED HERE AND MUST NOT BE. That is the *top
  # level's* flag, and the top level is a distro layer -- it decides which
  # components exist, instantiates a tree per target and drives them in order.
  # This package set is already the distro. See the boundary note in
  # `preConfigure`.
  #
  # A configure-time default target is a hiding place. Anything still tied to one
  # machine keeps working as long as that machine is the default, so the
  # dependency is never noticed -- it surfaces only for whichever target was not
  # chosen. With no default there is nowhere for it to hide.
  #
  # Note what this does to the store path, which is the point. The derivation
  # depends on the *list*, not on `targetPlatform`: two different lists should
  # give two different compilers, but the same list must give the same path no
  # matter which platform is being built for. That equality is the test -- if a
  # target dependency remains anywhere, the paths diverge and say so.
  #
  # Needs a GCC that has `--enable-backends` at all, i.e. `multi-target-0`. No
  # released GCC does, and autoconf accepts an unrecognised `--enable-*` with a
  # warning rather than an error -- so against a tarball this flag was silently
  # inert and the compiler came out single-target. That is why this package set
  # builds the branch and has no tarball arm; see `../../default.nix`.
  enableBackends ? null,
  # The four static libraries `gcc/` links out of sibling build directories.
  # Named as arguments so the boundary is visible at the top of the file rather
  # than buried in a shell fragment.
  libcpp,
  libdecnumber,
  libcody,
}:
let
  inherit (stdenv) hostPlatform;
  # No target in the name. A target-insensitive compiler still carrying a target
  # in its name would land at a different store path per target, which both
  # defeats the purpose and hides whether the contents actually differ.
  targetPrefix = "";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "${targetPrefix}${if langFortran then "gfortran" else "gcc"}";
  inherit version;

  src = monorepoSrc;

  outputs = [
    "out"
    "man"
    "info"
  ];

  patches = [
    # THE SEVEN BACKPORTS THAT USED TO BE HERE ARE GONE.
    #
    # They were `fetchpatch`es of upstream commits a GCC 15 tarball lacked.
    # This set now builds `multi-target-0`, which is cut from trunk, and all
    # seven are ancestors of it -- measured, seven for seven, with
    # `git merge-base --is-ancestor <sha> HEAD`. Left in place the first one
    # stopped the build with "Reversed (or previously applied) patch detected",
    # which is the good failure; a fuzzier hunk would have applied something
    # twice in silence.
    #
    # Recorded by sha so a bisect can find them again:
    #   f23bac62f46f  for_each_path: functional programming
    #   948eb0280077  find_a_program: separate from find_a_file
    #   073b4656d07e  simplify find_a_program and find_a_file
    #   6b008944e7bc  for_each_path: fix uninitialized ret (PR121806)
    #   f62f68e7c4bd  for_each_path: pass machine-specific
    #   a514707ffd7d  find_a_program: search with machine prefix
    #   7fb73dd7bb8a  mingw: drop obsolete STMP_FIXINC override

    # THE THREE POSTED-BUT-UNMERGED DRIVER PATCHES ARE ALSO GONE, AND THE WAY
    # THEY FAILED IS WORTH RECORDING.
    #
    # They extended the `<target>-as` preference to `PATH`. The branch already
    # carries them: `gcc/gcc.cc` defines `for_each_env_path` and calls it on
    # `env.get ("PATH")` in `find_a_program`, which is patch 2's whole point.
    #
    # But patch 1 did not fail cleanly. Its hunk 1 -- the one that *adds*
    # `for_each_env_path` -- reported "succeeded at 3100 (offset 117 lines)",
    # i.e. `patch` happily inserted a SECOND definition of a function already
    # present at line 3063, because an addition has no context to contradict.
    # Only hunk 2, which rewrites existing code, could see the conflict and
    # fail. Had the file been laid out slightly differently the build would
    # have gone on to a duplicate-definition error hundreds of lines from the
    # cause -- or, for a patch that only added, to no error at all.
    #
    # `git merge-base --is-ancestor` is the check that actually decides this,
    # and it cannot be run on a patch that was posted rather than committed.
    # So for these three the evidence is the source: `for_each_env_path` and
    # its `PATH` call site are in the tree.

    # `gcc/fix-collect2-paths.diff` IS ALSO GONE, AND THIS ONE IS NOT A
    # DUPLICATE -- IT IS SUPERSEDED, WHICH LOOKS THE SAME AND IS NOT.
    #
    # It threaded an `is_cross_compiler` flag through `collect2.cc` so that a
    # cross build would look for target-prefixed tools; 12 of its 18 hunks
    # applied to the branch and 6 failed, which is the worst possible outcome
    # and the reason it is removed rather than rebased.
    #
    # The branch answers the same question differently, and says so in the
    # source: `gcc/collect2.cc:62` ("THE FIXME THAT WAS HERE IS RESOLVED"),
    # `:106`, `:1246`. `CROSS_DIRECTORY_STRUCTURE` is never defined, so the
    # block the patch was working around was dead code; and "am I a cross
    # compiler" has no compile-time answer in a compiler with no single target,
    # so `REAL_{LD,NM,STRIP}_FILE_NAME` became per-target capabilities read
    # from the `-ftarget-config=` file instead. Rebasing the patch onto that
    # would reintroduce the compile-time answer the branch removed.
    #
    # The file stays in `../../15/gcc/` for the monolithic-set history; nothing
    # here references it any more.

    # From the posting to gcc-patches, which covers every component that links
    # libbacktrace. Take only this component's non-generated files: the
    # generated ones are rebuilt by `autoreconfHook269` below, against a GCC
    # slightly different from the one the patch was made against.
    (fetchpatch {
      name = "system-libbacktrace.patch";
      url = "https://inbox.sourceware.org/gcc-patches/20260814013206.3818461-1-git@JohnEricson.me/raw";
      includes = [
        "config/libbacktrace.m4"
        "gcc/configure.ac"
        "gcc/Makefile.in"
      ];
      hash = "sha256-i+J4B5f+zrXERPqJxwjEm/JHZhDsV6Gmxx/n9+G0shM=";
    })
  ];

  enableParallelBuilding = true;

  # The patches above touch `gcc/configure.ac`, and this is the one component
  # whose `configure` nothing regenerates on its own -- it has no
  # `Makefile.am`, so it is not part of any `autoreconf` the other packages
  # run. Only `gcc` is named, because reconfiguring the whole monorepo is both
  # slow and unnecessary.
  #
  # Regenerating rather than carrying `configure` in the patch keeps that patch
  # to what was actually written, and lets it apply to a tree whose generated
  # files have moved on.
  autoreconfFlags = "--verbose --force gcc";

  # `aclocal` finds the macro added under `config/` through `ACLOCAL_AMFLAGS`
  # in a `Makefile.am`, which `gcc` does not have. Without this the macro is
  # simply undefined, and `autoconf` leaves its name in the script as literal
  # shell rather than failing.
  preAutoreconf = ''
    export ACLOCAL_PATH="$PWD/config''${ACLOCAL_PATH:+:$ACLOCAL_PATH}"
  '';

  hardeningDisable = [
    "format" # Some macro-indirect formatting in e.g. libcpp
  ];

  strictDeps = true;

  depsBuildBuild = [ buildPackages.stdenv.cc ];


  nativeBuildInputs = [
    autoreconfHook269
    texinfo
    which
    gettext
  ]
  ++ lib.optional (perl != null) perl
  ++ lib.optionals fromVCS [
    flex
    bison
  ];

  buildInputs = [
    libbacktrace
    gmp
    libmpc
    mpfr
  ]
  ++ lib.optional (isl != null) isl
  ++ lib.optional (zlib != null) zlib;

  postUnpack = ''
    mkdir -p ./build
    buildRoot=$(readlink -e "./build")
  '';

  postPatch = ''
    configureScripts=$(find . -name configure)
    for configureScript in $configureScripts; do
      patchShebangs $configureScript
    done

    patchShebangs libbacktrace/install-debuginfo-for-buildid.sh
    patchShebangs runtest
  '';
  # THE DARWIN `substituteInPlace` THAT WAS HERE NAMED A FILE THAT DOES NOT
  # EXIST, AND WOULD HAVE FAILED THE BUILD RATHER THAN DOING NOTHING.
  #
  # It read `substituteInPlace gcc/config/darwin-c.c --replace 'if (stdinc)'
  # 'if (0)'`, to keep Darwin's framework directories out of the default search
  # path. GCC's sources became C++ in GCC 12: the file is `darwin-c.cc`, and
  # `ls gcc/config/darwin-c.c` on this branch reports no such file.
  # `substituteInPlace` errors on a missing file, so this is not a no-op -- it
  # is a `postPatch` that aborts, on the one platform it is gated to.
  #
  # It has never fired because nothing here builds Darwin: `hostPlatform
  # .isDarwin` is false on every arm this set has been exercised on, so a
  # guaranteed failure has sat behind a condition nobody takes. Deleted rather
  # than renamed, because the substitution's *content* is unverified too --
  # `--replace` (not `--replace-fail`) means that even with the right filename
  # it would silently do nothing if the text had moved, which for a change that
  # exists to remove `/System/Library/Frameworks` from the include path is the
  # dangerous direction. Whoever enables Darwin should re-derive it and prove it
  # fires.

  # THE TOP LEVEL IS NOT RUN. THIS BUILDS `gcc/` AND NOTHING ELSE.
  #
  # GCC's top-level build system is a distro: it decides which components
  # exist, instantiates a tree per target, orders them by dependency, drives
  # their configures and makes, and installs them into one prefix. That is what
  # a nixpkgs package set does, so running it from inside one puts a distro
  # inside a distro -- and every piece of jank this expression used to carry was
  # an artefact of the two disagreeing about who was in charge:
  #
  #   * `noconfigdirs="$noconfigdirs $target_libraries"`, a `substituteInPlace`
  #     on `configure` to stop the top level building the runtime libraries this
  #     set packages separately;
  #   * a fake `libiberty` build directory, three `touch`ed stamp files
  #     (`stamp-h`, `stamp-noasandir`, `stamp-picdir`) and a copy of the whole
  #     thing into `build-<config>/`, all to convince the top level that a
  #     sibling it wanted to build was already built;
  #   * `--enable-targets`, which only the top level takes.
  #
  # All of it is gone. `configureScript` is `gcc/configure`, and what the top
  # level would have built as siblings are derivations.
  #
  # THE BOUNDARY, ENUMERATED, because "it needs the top level" is not a
  # measurement. Building `gcc/` alone with nothing else present fails, in this
  # order, on exactly these files -- each one named by `make` itself:
  #
  #   ../build-<build>/libiberty/libiberty.a   build/genmodes
  #   ../build-<build>/libcpp/libcpp.a         build/genmatch
  #   ../libiberty/libiberty.a                 cc1
  #   ../libcpp/libcpp.a                       cc1
  #   ../libdecnumber/libdecnumber.a           cc1
  #   ../libcody/libcody.a                     cc1
  #   ../libbacktrace/.libs/libbacktrace.a     cc1-checksum.cc
  #
  # The last one does not appear here: `--with-system-libbacktrace` (see the
  # patch above) makes it a normal `buildInputs` dependency, which is what it
  # should have been all along. The rest are the four static libraries below.
  # `-I../libdecnumber` is a build-directory include (`gcc/Makefile.in:473`), so
  # that one contributes a generated header as well as an archive.
  #
  # The `build-<build>` copies are the *build machine's* builds of the same
  # libraries, which the generator programs link against. They come from
  # `buildGccPackages`, which is what that splice is for; in a native build the
  # two sides are the same derivation and nix shares it.
  preConfigure = ''
    cd "$buildRoot"

    sibling() {
      local dir="$1" lib="$2" a="$3"
      mkdir -p "$buildRoot/$dir"
      # `install -m` rather than `ln -s`: the archives are written into by
      # nothing here, but a read-only symlink into the store has produced
      # confusing failures in this tree before, and a copy costs nothing.
      install -m644 "$a" "$buildRoot/$dir/$lib"
    }

    sibling libiberty    libiberty.a    "${buildGccPackages.libiberty}/lib/libiberty.a"
    sibling libcpp       libcpp.a       "${libcpp}/lib/libcpp.a"
    sibling libdecnumber libdecnumber.a "${libdecnumber}/lib/libdecnumber.a"
    sibling libcody      libcody.a      "${libcody}/lib/libcody.a"
    install -m644 "${libdecnumber}/include/config.h" "$buildRoot/libdecnumber/config.h"
    install -m644 "${libdecnumber}/include/gstdint.h" "$buildRoot/libdecnumber/gstdint.h"

    sibling build-${stdenv.buildPlatform.config}/libiberty libiberty.a \
      "${buildGccPackages.libiberty}/lib/libiberty.a"
    sibling build-${stdenv.buildPlatform.config}/libcpp libcpp.a \
      "${buildGccPackages.libcpp}/lib/libcpp.a"
    sibling build-${stdenv.buildPlatform.config}/libdecnumber libdecnumber.a \
      "${buildGccPackages.libdecnumber}/lib/libdecnumber.a"
    sibling build-${stdenv.buildPlatform.config}/libcody libcody.a \
      "${buildGccPackages.libcody}/lib/libcody.a"

    mkdir -p "$buildRoot/gcc"
    cd "$buildRoot/gcc"
    configureScript=../../$sourceRoot/gcc/configure

    configureFlagsArray+=("GMPLIBS=-lmpc -lmpfr -lgmp")
  '';

  dontDisableStatic = true;

  configurePlatforms = [
    "build"
    "host"
  ];

  # FOURTEEN FLAGS WERE REMOVED FROM THIS LIST BECAUSE `gcc/configure` DOES NOT
  # HAVE THEM -- they were the top level's, and they were being accepted and
  # ignored.
  #
  # Measured by running `gcc/configure` with the old list and reading what it
  # said:
  #
  #   configure: WARNING: unrecognized options: --disable-dependency-tracking,
  #   --disable-serial-configure, --disable-bootstrap, --disable-decimal-float,
  #   --disable-install-libiberty, --disable-multilib, --enable-host-shared,
  #   --enable-default-pie, --without-included-gettext, --disable-fixincludes,
  #   --enable-linker-build-id, --enable-plugins, --with-gnu-as,
  #   --without-headers
  #
  # A warning is all autoconf gives, which is the same silence that made
  # `--enable-targets` inert against a release tarball. Several of these were
  # load-bearing when the top level was doing the driving -- `--disable-multilib`
  # and `--disable-bootstrap` in particular -- and the corresponding behaviour
  # now either has no top level to configure or belongs to another component's
  # derivation. Anything found missing later should come back as a flag
  # `gcc/configure` actually reads, not as one it merely tolerates.
  #
  # `--enable-shared` for the host is likewise gone with `--enable-host-shared`;
  # `enableShared` is left as an argument because the surrounding set passes it,
  # and it now feeds nothing here rather than feeding something ignored.
  configureFlags = [
    # `--target` IS PASSED, AND IT IS NOT A PRIVILEGED TARGET.
    #
    # `gcc/configure` requires one: with `--build` and `--host` only, `${target}`
    # comes out empty and `config.gcc` stops with `*** Configuration  not
    # supported` -- measured, note the doubled space where the triple should be.
    # It is the HOST's triple, so it says "this compiler runs here", and the
    # back-end list comes from `--enable-backends`, defaulted by the tree.
    #
    # The store path therefore depends on the host, which is correct and is
    # exactly what `mt-compare.nix` measures: it asks three different cross
    # package sets for the *build* machine's compiler, so the host is the same
    # on all three arms and the paths must be equal.
    "--target=${stdenv.hostPlatform.config}"
  ]
  ++ lib.optional (
    enableBackends != null
  ) "--enable-backends=${lib.concatStringsSep "," enableBackends}"
  ++ [
    "--enable-fast-install"
    "--disable-nls"
    "--enable-languages=${
      lib.concatStrings (
        lib.intersperse "," (
          lib.optional langC "c"
          ++ lib.optional langCC "c++"
          ++ lib.optional langFortran "fortran"
          ++ lib.optional langJava "java"
          ++ lib.optional langAda "ada"
          ++ lib.optional langGo "go"
          ++ lib.optional langObjC "objc"
          ++ lib.optional langObjCpp "obj-c++"
          ++ lib.optional langJit "jit"
        )
      )
    }"
    "--with-gnu-ld"
    # No `--with-as` / `--with-ld`: those bake `DEFAULT_ASSEMBLER` and
    # `DEFAULT_LINKER` as absolute store paths, and the driver then runs exactly
    # those binaries rather than deferring to the wrapped ones.
    #
    # Nothing about a target toolchain is asked here at all. `target-specs`
    # probes it afterwards, against whichever toolchain is in use, and the driver
    # finds the tools on `PATH` under their target-prefixed names via the
    # `find_a_program` patches above.
    "--with-system-zlib"
    "--with-system-libbacktrace"

    # GMPLIBS/GMPINC ARE NORMALLY HANDED DOWN BY THE TOP LEVEL, and `gcc/`
    # simply uses whatever it is given -- `AC_SUBST`ed, not probed. Building the
    # component alone, they are empty, and the failure is a link error 27,000
    # lines in: `undefined reference to mpfr_free_cache' from `context.cc`.
    # nixpkgs supplies the libraries through `buildInputs`, so only the `-l`
    # flags are needed; the same three the branch's own component-build script
    # passes.
    # (`GMPLIBS` contains spaces, so it is appended to `configureFlagsArray` in
    # `preConfigure` rather than written here, where the list is word-split.)
    "GMPINC="
    "ISLLIBS="
    "ISLINC="

    # No host platform headers are exposed to gcc, whatever the relationship
    # between build, host and target. cc-wrapper supplies the target libc
    # (`-idirafter <libc.dev>/include` and the corresponding `-B`/`-L` flags),
    # as in the LLVM package set, where `clang` likewise carries no libc
    # reference (`--without-headers` above). Naming one here --
    # `--with-sysroot`, `--with-native-system-header-dir` -- would make every
    # libc change rebuild the compiler, precisely the coupling this split
    # package set exists to remove.
    #
    # `fixincludes` likewise has nothing to do: it exists to copy the headers
    # gcc found and rewrite the ones it knows to be broken, and there are none
    # here. `--disable-fixincludes` USED TO BE PASSED AND IS NOT A
    # `gcc/configure` option (it is the top level's), so it was never doing
    # anything; what actually keeps `fixincludes` out of this build is that the
    # `make` target below is `all-gcc`-shaped and the component has no libc to
    # fix headers from. Per-target fixed headers belong to a `fixincludes`
    # component and to the wrapper that composes a target.
  ]
  ++ lib.optional enablePlugin "--enable-plugin";

  # `LIMITS_H_TEST` decides whether gcc's generated `syslimits.h` chains to the
  # target libc's `limits.h` (`#include_next`) or is emitted self-contained. It
  # defaults to a `[ -f $(BUILD_SYSTEM_HEADER_DIR)/limits.h ]` probe, which
  # necessarily fails here: we deliberately do not point the compiler at a
  # sysroot (see `configureFlags`), so there is no libc for it to find at build
  # time.
  #
  # Self-contained is the wrong answer regardless. Every target in this package
  # set is hosted, and cc-wrapper always supplies a libc, so the chained header
  # is what resolves correctly at *use* time. Without it, anything the libc's
  # `limits.h` defines and gcc's does not -- `PATH_MAX` being the common one --
  # goes missing from every libgcc source that needs it.
  makeFlags = [ "LIMITS_H_TEST=true" ];

  doCheck = false;

  # THE SOURCE-DERIVED HALF OF EVERY TARGET'S SPEC FILE IS BUILT AND INSTALLED
  # HERE, BECAUSE ONLY THIS BUILD CAN PRODUCE IT AND ONLY ANOTHER DERIVATION CAN
  # CONSUME IT.
  #
  # A target's spec file has two producers, and `gcc/Makefile.in:4039` is
  # explicit that they are different questions:
  #
  #   * `LINK_SPEC`, `STARTFILE_SPEC`, `ENDFILE_SPEC`, `LIB_SPEC`, `ASM_SPEC`,
  #     `CPP_SPEC`, `CC1_SPEC` and the multilib tables are strings in that back
  #     end's own `tm.h` chain and its `t-*` fragments. They are known HERE, at
  #     build time, and there is no probe that could recover them later.
  #   * everything that depends on which assembler and linker are installed is
  #     `target-specs/configure`'s, and is asked once the toolchain is known.
  #
  # `make multi-target-specs` writes the first half for every configured back
  # end, as `specs-src-<target>` and `mlib-specs-<target>`, plus the
  # `multi-target.manifest` that carries each target's `cpu_type` and
  # `option_defaults`. `target-specs/configure` takes all four by name
  # (`--with-source-specs`, `--with-cpu-type`, `--with-option-defaults`), and
  # `Makefile.tpl:2424` refuses to run without the manifest -- because probing
  # without it writes an EMPTY `*option_defaults` spec, which reads exactly like
  # a target that genuinely has none.
  #
  # None of it is installed by `make install`: the top level reads it out of the
  # build directory, in-place, because in a `./configure && make` world the
  # prober and the compiler share one tree. Here they are two derivations, so
  # the only way across is the store -- and this is the whole of what
  # `../target-specs` needs from `gcc`.
  #
  # THIS DOES NOT PUT A TARGET INTO THIS DERIVATION. It emits one file per back
  # end for EVERY back end the compiler serves, from the same list that already
  # decides the store path. `mt-compare.nix` is the check that this stayed true.
  # `all` is named explicitly because naming a second goal replaces the default
  # rather than adding to it.
  buildFlags = [
    "all"
    "multi-target-specs"
  ];

  postBuild = ''
    # `multi-target-specs` reports per-target failures on stderr and still
    # exits 0 -- deliberately, since a back end with no multilib table is a
    # real answer. So count the artefacts rather than trusting the status: an
    # empty `$out/.../multi-target` would be indistinguishable from a build
    # whose rule did not run, and `target-specs` would then fail one derivation
    # later with a message about the manifest.
    test -f multi-target.manifest
    nsrc=$(ls specs-src-* 2>/dev/null | wc -l)
    echo "gcc: multi-target-specs wrote $nsrc source-derived spec halves"
    test "$nsrc" -gt 0
  '';

  # THIS USED TO BE A LOOP THAT HAD NEVER MOVED A FILE, AND COULD NOT HAVE.
  #
  # It globbed `lib/gcc/*/"${version}"/plugin/include` with a
  # `test -d ... || continue`, on the belief that plugin headers land in a
  # per-target directory. Both halves of that path are wrong, and either alone
  # is fatal:
  #
  #   * there is no target component. `gcc/Makefile.in:859,863` make it
  #     `$(libdir)/gcc/$(version)/plugin/include` -- one compiler serves every
  #     back end, so `libsubdir` carries no triple on this branch;
  #   * `$(version)` there is `gcc/BASE-VER` (`17.0.0`), not the nixpkgs
  #     `version` (`17.0.0-multi-target-<rev>`).
  #
  # So the glob matched nothing, `continue` swallowed it, and the phase reported
  # success -- a mechanism present but never invoked, which reads as done and
  # does nothing. Measured on the built compiler: the directory is
  # `lib/gcc/17.0.0/plugin/include` and it holds the generated headers.
  #
  # The `moveToOutput` is gone rather than corrected, because this derivation
  # has no `dev` output (`outputs = [ "out" "man" "info" ]`), so `!outputDev`
  # is `out` and the move was a no-op even where the path existed. What is left
  # is the check: those headers are what `libgcc`'s `-I$(gcc_objdir)` has to
  # resolve against once it stops running its own inner gcc build, so their
  # absence must be an error and not a shrug.
  postInstall = ''
    plugininc="$out/lib/gcc/${release_version}/plugin/include"
    test -d "$plugininc" || {
      echo "gcc: no $plugininc." >&2
      echo "  \`install-plugin' puts the headers at" >&2
      echo "  \$(libdir)/gcc/\$(version)/plugin/include, with \$(version) taken" >&2
      echo "  from gcc/BASE-VER. If that layout has changed, change this path --" >&2
      echo "  do not restore the silent skip that hid it." >&2
      exit 1; }
    echo "gcc: $(ls "$plugininc" | wc -l) plugin headers at $plugininc"

    # Beside the per-target directories the driver searches, not inside one:
    # this is the input a per-target `target-specs` run consumes, and it is the
    # same file for all of them.
    # `release_version`, NOT `version`. Everything gcc installs under `lib/gcc/`
    # is keyed by `$(version)`, which is `gcc/BASE-VER` -- `17.0.0` -- while the
    # nixpkgs `version` is `17.0.0-multi-target-<rev>`. Using the latter here
    # put these files in a SECOND version directory beside the compiler's own,
    # which is exactly the "one name, several authorities" shape: measured, the
    # first build of this produced both `lib/gcc/17.0.0/` and
    # `lib/gcc/17.0.0-multi-target-491713a/`.
    srcspecs="$out/lib/gcc/${release_version}/multi-target"
    mkdir -p "$srcspecs"
    install -m644 multi-target.manifest multi-target.multilib "$srcspecs/"
    install -m644 specs-src-* "$srcspecs/"
    for f in mlib-specs-*; do
      test -f "$f" && install -m644 "$f" "$srcspecs/"
    done
    echo "gcc: installed $(ls "$srcspecs" | wc -l) files to $srcspecs"
  '';

  passthru = {
    inherit
      langC
      langCC
      langObjC
      langObjCpp
      langAda
      langFortran
      langGo
      ;
    isGNU = true;
  };

  meta = gcc_meta // {
    homepage = "https://gcc.gnu.org/";
  };
})
