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
  # Whether the driver's specs emit `-lgcc_s`. Derived as the monolithic build
  # derives it, Cygwin excluded: there they would also emit `-lgcc_eh`, which no
  # stage of this package set produces.
  enableTargetShared ? stdenv.targetPlatform.hasSharedLibraries && !stdenv.targetPlatform.isCygwin,
  # Targets this compiler serves, as a list of config triples. There is no
  # single-target build here: the compiler is always built with
  # `--enable-targets` and never with `--target`.
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
  # Needs a GCC with `--enable-targets`. No released GCC has one.
  enableTargets ? [ stdenv.targetPlatform.config ],
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
    (fetchpatch {
      name = "for_each_path-functional-programming.patch";
      url = "https://github.com/gcc-mirror/gcc/commit/f23bac62f46fc296a4d0526ef54824d406c3756c.diff";
      hash = "sha256-J7SrypmVSbvYUzxWWvK2EwEbRsfGGLg4vNZuLEe6Xe0=";
    })
    (fetchpatch {
      name = "find_a_program-separate-from-find_a_file.patch";
      url = "https://github.com/gcc-mirror/gcc/commit/948eb02800777d0318ee2a38bf32076afee739f2.diff";
      hash = "sha256-doXak3VfdWR/BP9XiJaU7uJz7rex78N1oaW6CqYwKaQ=";
    })
    (fetchpatch {
      name = "simplify-find_a_program-and-find_a_file.patch";
      url = "https://github.com/gcc-mirror/gcc/commit/073b4656d07e40f83a1db7f4462ab2d68b1875a2.diff";
      hash = "sha256-kW6ZHyMzsn7snUBuDx4XLriaFGWZ1fixNc9UH8O5els=";
    })
    (fetchpatch {
      name = "for_each_path-fix-uninitialized-ret-PR121806.patch";
      url = "https://github.com/gcc-mirror/gcc/commit/6b008944e7bc3a342a734c4fcf1001d63fd0a6f8.diff";
      hash = "sha256-preG5DdRX+a0NIebsapAVnqiLYtPjsR4H5BkAXL/65g=";
    })
    (fetchpatch {
      name = "for_each_path-pass-machine-specific.patch";
      url = "https://github.com/gcc-mirror/gcc/commit/f62f68e7c4bde0385fbd2dba3e926586dd2f1281.diff";
      hash = "sha256-NsgGnTMQTnz1c4urr6jeoGOzQ4xeJ/p+F53osNDYDCA=";
    })
    (fetchpatch {
      name = "find_a_program-search-with-machine-prefix.patch";
      url = "https://github.com/gcc-mirror/gcc/commit/a514707ffd7d58b140686036c2dece43ecb7d33c.diff";
      hash = "sha256-54/HzM+aeWq8CTkQu8Pualqc/LgRLS0+8EY8uPUsD+s=";
    })

    # Make --disable-fixinclude compatible with Cygwin
    (fetchpatch {
      name = "mingw-drop-obsolete-STMP_FIXINC-override.patch";
      url = "https://github.com/gcc-mirror/gcc/commit/7fb73dd7bb8aabab1416f0b28e6df45131a8e8ab.diff";
      hash = "sha256-FmFJISfXt+/TCRcd4rYfwacBiTqu+/OKw0VvLh46Hz0=";
    })

    # Not upstream yet; a follow-up to the series above (drop the `/raw` to
    # read them). They extend that series' `<target>-as` preference to `PATH`,
    # where we put the cross toolchain, so a cross compiler finds its tools
    # the way a native one does. See below for the problems `--with-as` and
    # `--with-ld` cause, and thus why we want to avoid them.
    (fetchpatch {
      name = "driver-factor-out-env-path-parsing.patch";
      url = "https://inbox.sourceware.org/gcc-patches/20260810065714.2215299-1-git@JohnEricson.me/raw";
      hash = "sha256-2qUUMWuyxX4mVaBPeNnHIiMl/aN7ejWM5stTSFWxD7g=";
    })
    (fetchpatch {
      name = "driver-search-PATH-ourselves.patch";
      url = "https://inbox.sourceware.org/gcc-patches/20260810065714.2215299-2-git@JohnEricson.me/raw";
      # The posted patch is against trunk, which spells this cast with the C++
      # operator.  GCC 15 still uses the CONST_CAST macro, and the line is
      # context rather than a change, so it cannot fuzz-match.  Rewrite it
      # here rather than keeping a forked copy of the whole patch.
      postFetch = ''
        substituteInPlace "$out" \
          --replace-fail 'string, const_cast<char **> (commands[i].argv),' \
                         'string, CONST_CAST (char **, commands[i].argv),'
      '';
      hash = "sha256-uD8xJxQus2qyNgNDN/63WnURNuUJFDkhaXPph7g/DIk=";
    })
    (fetchpatch {
      name = "driver-search-PATH-machine-prefix.patch";
      url = "https://inbox.sourceware.org/gcc-patches/20260810065714.2215299-3-git@JohnEricson.me/raw";
      hash = "sha256-Q5CJpJKD11kadIKselQdHgNe26GqojpyAAmlAyHnsB0=";
    })

    (getVersionFile "gcc/fix-collect2-paths.diff")

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
  ''
  # This should kill all the stdinc frameworks that gcc and friends like to
  # insert into default search paths.
  + lib.optionalString hostPlatform.isDarwin ''
    substituteInPlace gcc/config/darwin-c.c \
      --replace 'if (stdinc)' 'if (0)'
  '';

  preConfigure =
    # Don't built target libraries, because we want to build separately
    ''
      substituteInPlace configure \
        --replace 'noconfigdirs=""' 'noconfigdirs="$noconfigdirs $target_libraries"'
    ''
    # Cannot configure from src dir
    + ''
      cd "$buildRoot"

      mkdir -p "$buildRoot/libiberty/pic"
      cp ${buildGccPackages.libiberty}/lib/libiberty.a "$buildRoot/libiberty"
      cp ${buildGccPackages.libiberty}/lib/libiberty_pic.a "$buildRoot/libiberty/pic/libiberty.a"
      touch "$buildRoot/libiberty/stamp-noasandir"
      touch "$buildRoot/libiberty/stamp-h"
      touch "$buildRoot/libiberty/stamp-picdir"

      mkdir -p "$buildRoot/build-${stdenv.hostPlatform.config}"
      cp -r "$buildRoot/libiberty" "$buildRoot/build-${stdenv.hostPlatform.config}/libiberty"

      configureScript=../$sourceRoot/configure
    '';

  # Don't store the configure flags in the resulting executables.
  postConfigure = ''
    sed -e '/TOPLEVEL_CONFIGURE_ARGUMENTS=/d' -i Makefile
  '';

  dontDisableStatic = true;

  # No `target`. `--target` is not redundant here, it is the thing being
  # removed: passing it would give one machine a privileged position again and
  # hide anything still tied to it.
  configurePlatforms = [
    "build"
    "host"
  ];

  configureFlags = [
    # Force target prefix. The behavior if `--target` and `--host` are
    # specified is inconsistent: Sometimes specifying `--target` always causes
    # a prefix to be generated, sometimes it's only added if the `--host` and
    # `--target` differ. This means that sometimes there may be a prefix even
    # though nixpkgs doesn't expect one and sometimes there may be none even
    # though nixpkgs expects one (since not all information is serialized into
    # the config attribute). The easiest way out of these problems is to always
    # set the program prefix, so gcc will conform to our expectations.
    # Every target this compiler serves, none of them privileged.
    "--enable-targets=${lib.concatStringsSep "," enableTargets}"

    # No `--program-prefix`. The prefix existed to distinguish one target's
    # compiler from another's; there is one compiler now.

    "--disable-dependency-tracking"
    "--enable-fast-install"
    "--disable-serial-configure"
    "--disable-bootstrap"
    "--disable-decimal-float"
    "--disable-install-libiberty"
    "--disable-multilib"
    "--disable-nls"
    (lib.enableFeature enableShared "host-shared")
    (lib.enableFeature enableTargetShared "shared")
    "--enable-default-pie"
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
    (lib.withFeature (isl != null) "isl")
    "--without-headers"
    "--with-gnu-as"
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
    "--without-included-gettext"

    # No host platform headers are exposed to gcc, whatever the relationship
    # between build, host and target. cc-wrapper supplies the target libc
    # (`-idirafter <libc.dev>/include` and the corresponding `-B`/`-L` flags),
    # as in the LLVM package set, where `clang` likewise carries no libc
    # reference (`--without-headers` above). Naming one here --
    # `--with-sysroot`, `--with-native-system-header-dir` -- would make every
    # libc change rebuild the compiler, precisely the coupling this split
    # package set exists to remove.
    #
    # So `fixincludes` has nothing to do either: it exists to copy the headers
    # gcc found and rewrite the ones it knows to be broken. Left on, it falls
    # back to `/usr/include` and stops the build outright when that is missing.
    # `limits.h` and `syslimits.h` come from a separate prerequisite and are
    # unaffected.
    "--disable-fixincludes"

    "--enable-linker-build-id"
  ]
  ++ lib.optionals enablePlugin [
    "--enable-plugin"
    "--enable-plugins"
  ]
  ;

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

  # The plugin headers land under lib/gcc/<target>/<version>/, one directory per
  # target, so glob rather than naming a target.
  postInstall = ''
    for d in "$out"/lib/gcc/*/"${version}"/plugin/include; do
      test -d "$d" || continue
      moveToOutput "''${d#$out/}" "''${!outputDev}"
    done
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
