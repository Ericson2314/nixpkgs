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
  buildGccPackages,
  buildPackages,
  which,
  python3,

  # A threading library that is not part of the libc, for targets where the
  # libc alone does not offer the model we want — MinGW, whose only built-in
  # option is `win32`, with `mcfgthreads` being the case that motivates this.
  # `null` means "whatever the libc offers".
  #
  # Whatever is passed here has to be buildable without it, since it comes
  # before the libgcc that would otherwise provide the threading; see the
  # bootstrap chain in ../../README.md.
  threads ? null,

  # Build `libgcc_s` as well as `libgcc.a`. Only ever worth turning *off*: the
  # assertion below refuses to force it on where the default says it cannot
  # work, since what follows from that is a link failure much further away.
  enableShared ? __defaultEnableShared,

  # The following are arguments rather than a `let` bindings only so
  # that it is in scope for the default definition above.

  # Whether to build a shared libgcc.
  #
  # In addition to being the default, this is also the *maximal* condition --
  # by default we enable shared wherever possible, and enabling shared in more
  # cases should not work. That is why this is also used in the assert below.
  __defaultEnableShared ?
    # Of course if the platform as a whole doesn't support shared libraries, we
    # cannot either.
    stdenv.hostPlatform.hasSharedLibraries
    # libstdc++ and libgomp choke if we try to build a shared libgcc, because
    # the shared libgcc has fewer symbols, with the unwinder and the emulated-
    # TLS support in `libgcc_eh.a` instead, which those libraries don't link.
    #
    # We could perhaps patch those libraries to link `libgcc_eh.a` too as
    # needed, but it didn't feel worth the fight at this time.
    && !stdenv.hostPlatform.isCygwin
    # Shared needs something to link against. Normally that is the libc, on any
    # format -- PE/COFF included -- which is why every stage after the bootstrap
    # builds it. ELF additionally allows it *before* the libc exists, because a
    # shared object may keep undefined symbols; `libgcc_s.so` comes out with an
    # empty `DT_NEEDED`. A PE/COFF DLL must resolve everything at link time, so
    # there the bootstrap yields only `libgcc.a` -- all it is used for anyway.
    && (__haveLinkableLibc || stdenv.hostPlatform.isElf),

  # Whether the compiler has a libc that can actually be linked against, as
  # opposed to nothing at all or a headers-only stand-in.
  __haveLinkableLibc ? (stdenv.cc.libc or null) != null && !(stdenv.cc.libc.headersOnly or false),
}:
let
  # A libc needs libgcc to build, and a libgcc that can use the libc's threads
  # needs the libc, so this package is instantiated twice — see
  # `libgcc-no-libc` and `libgcc-libc` in the package set, the same split the
  # LLVM package set makes with `compiler-rt-no-libc` and `compiler-rt-libc`.
  #
  # Nothing here says which of the two it is. The difference is entirely in the
  # compiler it is handed: the bootstrap wrapper's `libc` is `preLibcHeaders`
  # (or nothing at all, on platforms without one), the later wrapper's is the
  # finished libc. Everything below reads that one value.
  libc = stdenv.cc.libc or null;

  # Which threading model may be used is decided by whatever provides the
  # threads — usually the libc, but the separate `threads` package where one
  # is given — so take it from there rather than guess, and pass it on in
  # `passthru` so that `libstdcxx`, which has to agree, reads the same answer
  # instead of probing for its own.
  #
  # A headers-only package declares no `threadModel`, and a real libc does.
  # That build exists only to get the libc built and is thrown away afterwards,
  # so there is nothing to be gained from threading it, and plenty to go wrong:
  # `gthr-posix.h` includes `<pthread.h>` unconditionally, which at that point
  # is either absent or a stand-in for a libc that does not exist yet.
  #
  # If, in the future, we ever wish to use the headers-only build to avoid
  # building those other libraries twice (other distros sometimes do this), we
  # would declare the threading model unconditonally, and then there would be
  # more cyclic symbol-level dependencies between them and us.
  #
  # libgcc (and libstdc++) read this attribute rather than probing the
  # compiler, which in a split package set is configured separately from the
  # runtimes and so can disagree. Only if we switched `cc-wrapper` to give GCC
  # "spec files" (more powerful than CLI flags) would be be able to get the
  # compiler `-v` flag correct with respect to the libraries it happend to be
  # wrapped with.
  #
  # A `threads` package wins over the libc: that is the whole point of asking
  # for one, and it is only ever passed to the builds that come after the libc.
  threadModel = threads.threadModel or (libc.threadModel or "single");
in

assert enableShared -> __defaultEnableShared;

stdenv.mkDerivation (finalAttrs: {
  pname = "libgcc" + lib.optionalString (libc == null) "-no-libc";
  inherit version;

  src = monorepoSrc;

  outputs = [
    "out"
    "dev"
  ];

  strictDeps = true;

  # `libiberty` AND FRIENDS ARE NOT libgcc'S -- MEASURED, AND KEPT ANYWAY, WITH
  # THE REASON WRITTEN DOWN.
  #
  # `grep libiberty libgcc/Makefile.in libgcc/configure.ac` reads **zero**.
  # Nothing in this library wants it. They are here for the `gcc/configure` and
  # `make` run in `preConfigure`, which exists only to produce `libgcc.mvars`
  # and the generated headers `-I$(gcc_objdir)` resolves. That run is a *gcc*
  # build happening inside libgcc's derivation, and these are its dependencies,
  # not ours.
  #
  # They go when it goes. What it is reaching for, exactly:
  #   `libgcc.mvars` -- two variables (`gcc/Makefile.in:3779-3784`):
  #     `GCC_CFLAGS`, which describes *gcc's* build and whose `-isystem
  #     ./include` is relative to gcc's build directory (hence the
  #     `mkdir -p "$buildRoot/gcc/include"` below, which exists to stop an
  #     illegitimate flag from erroring), and `INHIBIT_LIBC_CFLAGS`, which is
  #     `-Dinhibit_libc` and is legitimate;
  #   `-I$(gcc_objdir)` (`libgcc/Makefile.in:284`) -- `tconfig.h`, `tm.h`,
  #     `options.h`, `insn-constants.h`. Legitimate in kind (libgcc is one
  #     machine's library) but they have to come from somewhere, and today
  #     nothing installs a multi-target compiler's per-target generated headers.
  #     That is what stands between this derivation and a standalone libgcc.
  depsBuildBuild = [
    buildPackages.stdenv.cc
    buildGccPackages.libiberty
    buildGccPackages.libcpp
    buildGccPackages.libdecnumber
    buildGccPackages.libcody
  ];

  nativeBuildInputs = [
    autoreconfHook269
    which
    python3
  ];

  # The `gthr-<model>.h` header for a non-libc threading model includes that
  # library's own headers, and the built `libgcc_s` links against it, so it has
  # to be on the include and library paths here.
  buildInputs = lib.optional (threads != null) threads;

  patches = [
    # FOUR BACKPORTS REMOVED, for the same reason as the seven in `../gcc`:
    # each is an ancestor of `multi-target-0`, measured with
    # `git merge-base --is-ancestor <sha> HEAD`, four for four.
    #
    #   493aae4b034d  delete MACHMODE_H
    #   e5d853bbe9b0  custom threading model
    #   77144dd3b673  no PIE cflags
    #   9947930b7ae9  no target system root
    (fetchpatch {
      name = "regular-libdir-includedir.patch";
      url = "https://inbox.sourceware.org/gcc-patches/20250717174911.1536129-1-git@JohnEricson.me/raw";
      # The posted patch carries the regenerated `configure` as well, and one
      # of its hunks no longer applies to trunk. `autoreconfFlags` below
      # regenerates that file anyway, so take only the input: a partially
      # applied generated file is the worst of the outcomes available.
      excludes = [ "libgcc/configure" ];
      hash = "sha256-Bx3xx0Uql5Lcv1UORzlFjUhikPWcirJYCDHZRgS2fds=";
    })
    (getVersionFile "libgcc/force-regular-dirs.patch")
  ];

  autoreconfFlags = "--install --force --verbose . libgcc";

  postUnpack = ''
    mkdir -p ./build
    buildRoot=$(readlink -e "./build")
  '';

  postPatch =
    # Both halves of this are ELF-specific, so it is applied only there.
    # `crti.o`/`crtn.o` are an ELF convention; forcing the rule on a PE/COFF
    # target makes the build assemble the generic ELF `crti.S` with a PE
    # assembler, which fails outright. And on those targets `SHLIB_LC` is not
    # `-lc` but the list of system import libraries the DLL needs, so blanking
    # it would leave the shared libgcc missing its real dependencies.
    #
    # Trick to build a gcc that is capable of emitting shared libraries *without* having the
    # hostPlatform libc available beforehand.  Taken from:
    #   https://web.archive.org/web/20170222224855/http://frank.harvard.edu/~coldwell/toolchain/
    #   https://web.archive.org/web/20170224235700/http://frank.harvard.edu/~coldwell/toolchain/t-linux.diff
    lib.optionalString (enableShared && stdenv.hostPlatform.isElf) (
      let

        # crt{i,n}.o are the first and last (respectively) object file
        # linked when producing an executable.  Traditionally these
        # files are delivered as part of the C library, but on GNU
        # systems they are in fact built by GCC.  Since libgcc needs to
        # build before glibc, we can't wait for them to be copied by
        # glibc.  At this early pre-glibc stage these files sometimes
        # have different names.
        crtstuff-ofiles =
          if stdenv.hostPlatform.isPower64 then "ecrti.o ecrtn.o ncrti.o ncrtn.o" else "crti.o crtn.o";

        # Normally, `SHLIB_LC` is set to `-lc`, which means that
        # `libgcc_s.so` cannot be built until `libc.so` is available.
        # The assignment below clobbers this variable, removing the
        # `-lc`.
        #
        # On PowerPC we add `-mnewlib`, which means "libc has not been
        # built yet".  This causes libgcc's Makefile to use the
        # gcc-built `{e,n}crt{n,i}.o` instead of failing to find the
        # versions which have been repackaged in libc as `crt{n,i}.o`
        #
        SHLIB_LC = lib.optionalString stdenv.hostPlatform.isPower64 "-mnewlib";

      in
      ''
        echo 'libgcc.a: ${crtstuff-ofiles}' >> libgcc/Makefile.in
        echo 'SHLIB_LC=${SHLIB_LC}' >> libgcc/Makefile.in
      ''

      # Meanwhile, crt{i,n}.S are not present on certain platforms
      # (e.g. LoongArch64), resulting in the following error:
      #
      # No rule to make target '../../../gcc-xx.x.x/libgcc/config/loongarch/crti.S', needed by 'crti.o'.  Stop.
      #
      # For LoongArch64 and S390, a hacky workaround is to simply touch them,
      # as the platform forces .init_array support.
      #
      # https://www.openwall.com/lists/musl/2022/11/09/3
      #
      # 'parsed.cpu.family' won't be correct for every platform.
      + (lib.optionalString
        (stdenv.hostPlatform.isLoongArch64 || stdenv.hostPlatform.isS390 || stdenv.hostPlatform.isAlpha)
        ''
          touch libgcc/config/${stdenv.hostPlatform.parsed.cpu.family}/crt{i,n}.S
        ''
      )
      + lib.optionalString (stdenv.hostPlatform.isPower && !stdenv.hostPlatform.isPower64) ''
        touch libgcc/config/rs6000/crt{i,n}.S
      ''
    )

    # gcc's installed `limits.h` chains to the target libc's with
    # `#include_next`. Where the compiler has a libc — headers-only or real —
    # that resolves, and it has to: some targets build libgcc sources that need
    # what only the libc header defines. Where it does not, the chain has
    # nowhere to land, and
    # even configure's `AC_PROG_CPP` probe fails -- it includes `<limits.h>`
    # precisely because that "exists even on freestanding compilers" -- after
    # which configure falls back to `/lib/cpp` and reports that as the error.
    #
    # Only in that case, put gcc's own `glimits.h` earlier on the include path
    # for this build. That is the self-contained variant, the same file gcc
    # installs when configured against no libc, so nothing is invented here.
    # The compiler keeps shipping the chained header either way, which is what
    # has to stay correct for everything compiled against a real libc later.
    + lib.optionalString (libc == null) ''
      mkdir -p "$NIX_BUILD_TOP/freestanding-include"
      cp gcc/glimits.h "$NIX_BUILD_TOP/freestanding-include/limits.h"
      export NIX_CFLAGS_COMPILE="-isystem $NIX_BUILD_TOP/freestanding-include ''${NIX_CFLAGS_COMPILE-}"
    ''
    + ''
      sourceRoot=$(readlink -e "./libgcc")
    '';

  enableParallelBuilding = true;

  preConfigure = ''
    cd "$buildRoot"

    # The inner gcc build's siblings, same enumerated boundary as the `gcc`
    # derivation's; all on the BUILD machine, since that is where its
    # generators run.
    for l in libiberty:${buildGccPackages.libiberty}/lib/libiberty.a \
             libcpp:${buildGccPackages.libcpp}/lib/libcpp.a \
             libdecnumber:${buildGccPackages.libdecnumber}/lib/libdecnumber.a \
             libcody:${buildGccPackages.libcody}/lib/libcody.a; do
      d=''${l%%:*}; a=''${l#*:}
      mkdir -p "$buildRoot/build-${stdenv.buildPlatform.config}/$d"
      install -m644 "$a" "$buildRoot/build-${stdenv.buildPlatform.config}/$d/''${a##*/}"
    done

    mkdir -p "$buildRoot/gcc"
    cd "$buildRoot/gcc"

    (
  ''
  # `AS`, `CC`, `CPP` and `LD` still name the *target* tools at this point,
  # under their machine-prefixed names. Snapshot them before the
  # `*_FOR_BUILD` assignments below overwrite them.
  #
  # Deriving `AS_FOR_TARGET` from `$AS` *after* `AS=$AS_FOR_BUILD` asked for
  # the basename of the build assembler -- plain `as` -- inside the target
  # compiler's `bin`, and a cross wrapper installs only prefixed names, so
  # the path did not exist. Likewise `ld`.
  #
  # That is not an error `gcc/configure` reports. It probes the target
  # assembler and linker for capabilities, and a probe it cannot run simply
  # records "no"; with neither tool found, *every* `gcc_cv_as_*`/`gcc_cv_ld_*`
  # answer came back "no". The one that matters here is
  # `HAVE_LD_EH_FRAME_HDR`: `unwind-dw2-fde-dip.c` gates `USE_PT_GNU_EH_FRAME`
  # on it, so without it the unwinder is compiled with no `dl_iterate_phdr`
  # lookup at all -- only the `__register_frame` registry, which nothing
  # populates for normally linked objects. libgcc and libstdc++ then build,
  # link and install perfectly cleanly, and every C++ `throw` finds no FDE
  # and calls `std::terminate`.
  #
  # `CPP` in particular is not always exported, so fall back to the
  # machine-prefixed name the wrappers install.
  + ''
    targetAs=$(basename "''${AS:-${stdenv.hostPlatform.config}-as}")
    targetCc=$(basename "''${CC:-${stdenv.hostPlatform.config}-cc}")
    targetCpp=$(basename "''${CPP:-${stdenv.hostPlatform.config}-cpp}")
    targetLd=$(basename "''${LD:-${stdenv.hostPlatform.config}-ld}")

    export AS_FOR_BUILD=${lib.getExe' buildPackages.stdenv.cc "$(basename $AS_FOR_BUILD)"}
    export CC_FOR_BUILD=${lib.getExe' buildPackages.stdenv.cc "$(basename $CC_FOR_BUILD)"}
    export CPP_FOR_BUILD=${lib.getExe' buildPackages.stdenv.cc "$(basename $CPP_FOR_BUILD)"}
    export CXX_FOR_BUILD=${lib.getExe' buildPackages.stdenv.cc "$(basename $CXX_FOR_BUILD)"}
    export LD_FOR_BUILD=${lib.getExe' buildPackages.stdenv.cc.bintools "$(basename $LD_FOR_BUILD)"}

    export AS=$AS_FOR_BUILD
    export CC=$CC_FOR_BUILD
    export CPP=$CPP_FOR_BUILD
    export CXX=$CXX_FOR_BUILD
    export LD=$LD_FOR_BUILD

    export AS_FOR_TARGET=${lib.getExe' stdenv.cc "$targetAs"}
    export CC_FOR_TARGET=${lib.getExe' stdenv.cc "$targetCc"}
    export CPP_FOR_TARGET=${lib.getExe' stdenv.cc "$targetCpp"}
    export LD_FOR_TARGET=${lib.getExe' stdenv.cc.bintools "$targetLd"}

    export NIX_CFLAGS_COMPILE_FOR_BUILD+=' -DGENERATOR_FILE=1'

    "$sourceRoot/../gcc/configure" $topLevelConfigureFlags

    sed -e 's,libgcc.mvars:.*$,libgcc.mvars:,' -i Makefile

    make \
      config.h \
      libgcc.mvars \
      tconfig.h \
      tm.h \
      options.h \
      insn-constants.h \
      version.h
    )
    mkdir -p "$buildRoot/gcc/include"

    mkdir -p "$buildRoot/gcc/${stdenv.hostPlatform.config}/libgcc"
    cd "$buildRoot/gcc/${stdenv.hostPlatform.config}/libgcc"
    configureScript=$sourceRoot/configure
    chmod +x "$configureScript"

    export AS_FOR_BUILD=${lib.getExe' buildPackages.stdenv.cc "$(basename $AS_FOR_BUILD)"}
    export CC_FOR_BUILD=${lib.getExe' buildPackages.stdenv.cc "$(basename $CC_FOR_BUILD)"}
    export CPP_FOR_BUILD=${lib.getExe' buildPackages.stdenv.cc "$(basename $CPP_FOR_BUILD)"}
    export CXX_FOR_BUILD=${lib.getExe' buildPackages.stdenv.cc "$(basename $CXX_FOR_BUILD)"}
    export LD_FOR_BUILD=${lib.getExe' buildPackages.stdenv.cc.bintools "$(basename $LD_FOR_BUILD)"}

    export AS=${lib.getExe' stdenv.cc "$(basename $AS)"}
    export CC=${lib.getExe' stdenv.cc "$(basename $CC)"}
    export CPP=${lib.getExe' stdenv.cc "$(basename $CPP)"}
    export CXX=${lib.getExe' stdenv.cc "$(basename $CXX)"}
    export LD=${lib.getExe' stdenv.cc.bintools "$(basename $LD)"}

    export AS_FOR_TARGET=${lib.getExe' stdenv.cc "$(basename $AS_FOR_TARGET)"}
    export CC_FOR_TARGET=${lib.getExe' stdenv.cc "$(basename $CC_FOR_TARGET)"}
    export CPP_FOR_TARGET=${lib.getExe' stdenv.cc "$(basename $CPP_FOR_TARGET)"}
    export LD_FOR_TARGET=${lib.getExe' stdenv.cc.bintools "$(basename $LD_FOR_TARGET)"}
  ''
  + lib.optionalString stdenv.hostPlatform.isMusl ''
    NIX_CFLAGS_COMPILE_OLD=$NIX_CFLAGS_COMPILE
    NIX_CFLAGS_COMPILE+=' -isystem ${stdenv.cc.cc}/lib/gcc/${stdenv.hostPlatform.config}/${version}/include-fixed'
  '';

  topLevelConfigureFlags = [
    "--build=${stdenv.buildPlatform.config}"
    "--host=${stdenv.buildPlatform.config}"
    "--target=${stdenv.hostPlatform.config}"

    "--disable-bootstrap"
    "--disable-multilib"
    "--enable-languages=c"

    "--disable-fixincludes"
    "--disable-intl"
    "--disable-lto"
    "--disable-libatomic"
    "--disable-libbacktrace"
    "--disable-libcpp"
    "--disable-libssp"
    "--disable-libquadmath"
    "--disable-libgomp"
    "--disable-libvtv"
    "--disable-vtable-verify"

    "--with-system-zlib"

    # `gcc/configure` includes `system.h`, which includes `gmp.h`, in EVERY
    # feature probe. The branch turns a missing `gmp.h` into a hard error
    # naming itself -- it used to sail past and write about fifty wrong answers
    # into `auto-host.h`, `rlim_t` among them, whose bogus definition then fails
    # every compile with an error that names anything but the cause.
    #
    # The headers wanted are the BUILD machine's: this configure runs there.
    # When the top level was doing the driving it passed `GMPINC` down and this
    # was invisible.
    "GMPINC=-I${lib.getDev buildPackages.gmp}/include"

    # State this rather than leave it to be inferred (see below): configure
    # works it out from `host != target` alone, so a native build of the
    # pre-libc stage would come out `false` and compile every file against a
    # libc that is not there yet. A value given here wins, since configure only
    # defaults it, with `: ${inhibit_libc=false}`.
    "inhibit_libc=${if libc == null then "true" else "false"}"
  ]
  # NO `--with-sysroot=` / `--with-native-system-header-dir=`. They used to be
  # here so that `gcc/configure` would derive `target_header_dir` and decide
  # `inhibit_libc` from it. `target_header_dir` is GONE on this branch --
  # `gcc/configure.ac:2197` is literally `dnl target_header_dir is GONE.`, and
  # is the file's only occurrence -- so both flags were inert. `inhibit_libc`
  # is stated above instead, and the symbols it decides are asserted in
  # `postInstall` rather than trusted.
  ++
    lib.optional (!stdenv.hostPlatform.isRiscV)
      # RISC-V does not like it being empty
      "--with-multilib-list="
  ++
    lib.optional (stdenv.hostPlatform.libc == "glibc")
      # Cheat and use previous stage's glibc to avoid infinite recursion. As
      # of GCC 11, libgcc only cares if the version is greater than 2.19,
      # which is quite ancient, so this little lie should be fine.
      "--with-glibc-version=${buildPackages.glibc.version}";

  configurePlatforms = [
    "build"
    "host"
  ];

  configureFlags = [
    "--disable-dependency-tracking"
    "gcc_cv_target_thread_file=${threadModel}"
    # $CC cannot link binaries, let alone run then
    "cross_compiling=true"
    "--enable-static"

    (lib.enableFeature enableShared "shared")
  ];

  # Set the variable back the way it was, see corresponding code in
  # `preConfigure`.
  postConfigure = lib.optionalString stdenv.hostPlatform.isMusl ''
    NIX_CFLAGS_COMPILE=$NIX_CFLAGS_COMPILE_OLD
  '';

  makeFlags = [ "MULTIBUILDTOP:=../" ];

  postInstall = ''
    install -c -m 644 gthr-default.h "$dev/include"
  ''
  # THE `inhibit_libc` GUARD. It is the whole reason the sysroot flags were
  # here, and it is decidable, so decide it.
  #
  # `-Dinhibit_libc` drops split-stack entirely (`generic-morestack.c`,
  # `-thread.c`), most of libgcov (`libgcov-profiler/-interface/-merge/
  # -driver.c`) and the `dl_iterate_phdr` FDE lookup in `unwind-dw2-fde-dip.c`
  # -- **with no change to the installed file names**, which is exactly why a
  # crippled libgcc looks like a good one. Nothing about the build's exit
  # status, its output paths or its file list distinguishes the two.
  #
  # So ask the archive. Zero versus non-zero is decidable, and the same probe
  # run on the `no-libc` build reports the opposite, which is the control: if
  # this ever passed on both, it would be measuring nothing.
  + ''
    libgcc_a="$out/lib/libgcc.a"
    test -f "$libgcc_a"

    # A tool that is not there scores 0, in the direction that makes the
    # with-libc arm look broken and the no-libc arm look correct. Assert it
    # runs before believing any count it produces.
    "''${NM:-nm}" --version > /dev/null

    count() {
      "''${NM:-nm}" --defined-only "$libgcc_a" > libgcc-syms.txt
      grep -c "$1" libgcc-syms.txt || true
    }

    ngcov=$(count '__gcov_')
    nsplit=$(count '__splitstack_')

    # Reported, not asserted: split-stack exists only where the back end builds
    # `generic-morestack.c` (i386 and a few others), so zero is the correct
    # answer on most targets and an assertion on it would fire for the wrong
    # reason. `__gcov_*` is the one libgcov builds everywhere.
    echo "libgcc: __gcov_* = $ngcov, __splitstack_* = $nsplit (reported only)"
  ''
  + (
    if libc == null then
      ''
        # The control arm. These MUST be absent: this libgcc was built with
        # `inhibit_libc=true`, and if the symbols showed up here the assertion
        # on the other arm would be proving nothing.
        if [ "$ngcov" -ne 0 ]; then
          echo "libgcc: built with inhibit_libc=true, yet libgcc.a defines" >&2
          echo "libgcc: $ngcov __gcov_* symbols." >&2
          echo "libgcc: that means inhibit_libc did not take effect, and the" >&2
          echo "libgcc: check on the with-libc build is not measuring anything." >&2
          exit 1
        fi
      ''
    else
      ''
        if [ "$ngcov" -eq 0 ]; then
          echo "libgcc: this libgcc was built against a real libc, so" >&2
          echo "libgcc: libgcov must be present -- but __gcov_* = 0." >&2
          echo "libgcc: something set inhibit_libc, and the result installs" >&2
          echo "libgcc: under the same file names as a good one." >&2
          exit 1
        fi
      ''
  );

  doCheck = true;

  passthru = {
    isGNU = true;
    inherit threadModel;
  };

  meta = gcc_meta // {
    homepage = "https://gcc.gnu.org/";
  };
})
