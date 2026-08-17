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

  # THE INNER `gcc/configure` RUN IS GONE, AND SO IS EVERY TOOL-VARIABLE EXPORT
  # WITH IT. THIS BUILDS `libgcc/` AND NOTHING ELSE.
  #
  # What used to be here: a whole second configure and partial build of GCC's
  # `gcc/` component, driven with a fifteen-flag `topLevelConfigureFlags` list
  # and about twenty `export`s of build-machine and target-machine tool
  # variables, to produce two things --
  #
  #   * `libgcc.mvars`, whose two variables (`gcc/Makefile.in:3801-3806`) were
  #     `GCC_CFLAGS` (a description of GCC'S OWN BUILD, whose `-isystem
  #     ./include` is relative to gcc's build directory -- which is why this
  #     derivation used to `mkdir -p "$buildRoot/gcc/include"`, purely to stop
  #     an illegitimate flag from erroring) and `INHIBIT_LIBC_CFLAGS`;
  #   * the generated headers that `-I$(gcc_objdir)` resolved.
  #
  # libgcc now answers both itself, and asks the COMPILER for the third thing:
  #
  #   * `libgcc/configure.ac:263-302` detects in-tree versus standalone by
  #     looking for a sibling `gcc/libgcc.mvars`, and when there is none runs
  #     `$CC -print-target-header-dir`. `libgcc/Makefile.in:323` is now
  #     `-I$(gcc_target_incdir)` rather than `-I$(gcc_objdir)`.
  #   * `Makefile.in:216-222` defines `GCC_CFLAGS` itself in the standalone
  #     case, without the build-directory-relative flag.
  #   * `configure.ac:318-330` PROBES `inhibit_libc` -- it compiles
  #     `#include <stdio.h>` against the headers these objects will actually
  #     use -- instead of inheriting the host gcc's single answer.
  #
  # SO THE ONLY INPUT THIS COMPONENT NEEDS IS A COMPILER, ARRIVING AS AN
  # ORDINARY DERIVATION INPUT. That is the whole of the claim this task was
  # about, and it is now the code rather than a prediction.
  #
  # `--host=<the library's machine>` AND NO `--target`: `configurePlatforms`
  # below is `[ "build" "host" ]`. libgcc is one machine's library; the top
  # level renaming its `--target` into libgcc's `--host` was the inversion.
  #
  # The catch-all it replaces was not merely inelegant. `-I$(gcc_objdir)` served
  # whatever `tm.h` the sibling gcc build directory happened to hold, and on a
  # multi-target build that is the PRIMARY back end's -- so in the sibling case
  # every target's libgcc was compiled against i386's `tm.h`. Live, not latent.
  # `which` and `python3` were the INNER gcc build's: its generator scripts
  # want them, libgcc's own configure and Makefile do not. They go with it.
  nativeBuildInputs = [ autoreconfHook269 ];

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
      # `libgcc/Makefile.in` IS EXCLUDED TOO, AND IS RE-EXPRESSED BELOW AS
      # `substituteInPlace`. Its last hunk stopped applying: the branch inserted
      # a comment block between `install-unwind_h` and `install-gcov_h`, and the
      # hunk's trailing context is that block. Six of seven hunks applied, which
      # is the worst outcome available -- `patch` exits non-zero, but a tree with
      # six of seven applied is what it leaves behind, and `--fuzz` up to 5 makes
      # it strictly worse (two failures rather than one), measured.
      #
      # The four edits it actually makes are mechanical, and `substituteInPlace
      # --replace-fail` states each one as an assertion: a pattern that has
      # stopped existing is an error naming the pattern, rather than an offset
      # that quietly lands somewhere else.
      #
      # IF YOU CHANGE `excludes`, `includes` OR THE URL, CHANGE `hash` TOO.
      # This is a fixed-output derivation: its store path is a function of the
      # name and the hash and NOTHING ELSE, so with the hash unchanged nix
      # considers the existing path valid and never re-runs the recipe. Adding
      # the exclusion below did nothing at all on the first attempt -- the build
      # kept applying the unfiltered patch and failing identically, so a correct
      # fix looked like no fix. Set the hash to a wrong value, read the `got:`
      # line, and put that back. The general shape is worth remembering: a
      # correct edit to an FOD's recipe is INERT until its hash moves.
      excludes = [
        "libgcc/configure"
        "libgcc/Makefile.in"
      ];
      hash = "sha256-IxzhTA/18rxbL4FomzlNLeAer7MP/aLEsh4g2C5JvBY=";
    })
    (getVersionFile "libgcc/force-regular-dirs.patch")
  ];

  autoreconfFlags = "--install --force --verbose . libgcc";

  postUnpack = ''
    mkdir -p ./build
    buildRoot=$(readlink -e "./build")
  '';

  postPatch =
    # THE `libgcc/Makefile.in` HALF OF `regular-libdir-includedir.patch`, as
    # assertions rather than as context matching. See the `excludes` above for
    # why it is not a patch any more.
    #
    # What it does, in one sentence: libgcc installs into the ordinary
    # `$(libdir)` and `$(includedir)` instead of
    # `$(libdir)/gcc/<triple>/<version>`, which is the layout a package manager
    # wants and the only reason `$out/lib/libgcc.a` is where every consumer
    # expects it. `libsubdir` is left defined and simply stops being used; the
    # upstream patch also deletes it and `real_host_noncanonical`, which is
    # tidier and is a bigger diff to keep rebased for no behavioural gain.
    ''
      substituteInPlace libgcc/Makefile.in \
        --replace-fail 'shlib_slibdir = @slibdir@' \
                       'shlib_slibdir = @slibdir@
      includedir = @includedir@' \
        --replace-fail '"libsubdir=$(libsubdir)" \' \
                       '"includedir=$(includedir)" \' \
        --replace-fail 'inst_libdir = $(libsubdir)$(MULTISUBDIR)' \
                       'inst_libdir = $(libdir)$(MULTISUBDIR)' \
        --replace-fail '$(DESTDIR)$(libsubdir)/include' \
                       '$(DESTDIR)$(includedir)'

      # `--replace-fail` fires on the FIRST absent pattern, so a later one that
      # is present four times and becomes present zero times would still be
      # caught -- but one that changes from four occurrences to one would not.
      # Count what is left instead of trusting the replace.
      if grep -q 'libsubdir)/include' libgcc/Makefile.in; then
        echo "libgcc: libsubdir/include survives in Makefile.in:" >&2
        grep -n 'libsubdir)/include' libgcc/Makefile.in >&2
        exit 1
      fi
    ''
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
    + lib.optionalString (enableShared && stdenv.hostPlatform.isElf) (
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
    configureScript=$sourceRoot/configure
    chmod +x "$configureScript"

    # NO IN-TREE-DETECTION GUARD HERE. One was written and was WRONG in the
    # direction that matters: it globbed `"$up/../../"*"/gcc/libgcc.mvars"` and
    # fed the unmatched glob to `test -f`, which with more than one argument is
    # not the test it looks like -- it reported a sibling gcc build directory in
    # a tree that has none, and stopped the build.
    #
    # The question it was trying to ask is answered properly in `postConfigure`
    # below, from configure's own recorded answer rather than from a
    # reconstruction of configure's search.
    # THE MUSL `-isystem .../include-fixed` DANCE THAT WAS HERE IS GONE, AND IT
    # HAD NEVER ADDED A DIRECTORY THAT EXISTS.
    #
    # It saved `NIX_CFLAGS_COMPILE`, appended
    # `-isystem $cc/lib/gcc/<triple>/<version>/include-fixed` for the configure
    # run, and restored it in `postConfigure`. The path is wrong on two counts,
    # and each alone is fatal:
    #
    #   * the layout is `lib/gcc/<version>/<triple>/`, not
    #     `lib/gcc/<triple>/<version>/` -- one compiler serves every back end,
    #     so the version comes first (`gcc/Makefile.in:859`);
    #   * `${version}` is the nixpkgs version (`17.0.0-multi-target-<rev>`),
    #     while every `lib/gcc/` path gcc writes is keyed by `gcc/BASE-VER`.
    #
    # Measured on the built compiler: `lib/gcc/` contains exactly `17.0.0`, and
    # there is no `include-fixed` anywhere under it -- fixed headers are
    # `../include-fixed`'s output now, and gcc's own `stmp-fixinc` rule is gone.
    # `-isystem` on a nonexistent directory is silently ignored, so this flag
    # had no effect on any build, ever.
    #
    # It is exactly the shape already found in the plugin-header `postInstall`
    # of `../gcc`: a path assembled from `<triple>` and the wrong `version`,
    # which cannot match, in a construct that cannot complain.
  '';

  # ASK THE COMPILER WHAT IT ANSWERED, BECAUSE CONFIGURE'S OWN CHECK CANNOT
  # DISTINGUISH THE TWO CASES THAT MATTER TO US.
  #
  # `configure.ac` errors if `-print-target-header-dir` names nothing or names a
  # directory with no `tm.h` -- but it is equally happy with the in-tree path,
  # and equally happy with a header directory belonging to a DIFFERENT target,
  # since every target's has a `tm.h`. Both would build, and both would produce
  # a `libgcc.a` for the wrong machine under the right file names. So read the
  # two answers back out of `config.log` and require them.
  postConfigure = ''
    test -f config.log || {
      echo "libgcc: no config.log; cannot establish which headers were used." >&2
      exit 1; }

    incdir=$(sed -n "s|^gcc_target_incdir='\\(.*\\)'$|\\1|p" config.log | tail -1)
    test -n "$incdir" || \
      incdir=$(awk '/where this targets generated headers come from|generated headers come from/ { getline; sub(/^configure:[0-9]*: result: /, ""); print; exit }' config.log)
    test -n "$incdir" || {
      echo "libgcc: config.log does not say where the generated headers came" >&2
      echo "  from. This check is reading nothing, which must not pass." >&2
      exit 1; }

    case "$incdir" in
      *"/${stdenv.hostPlatform.config}/include") ;;
      *) echo "libgcc: headers came from '$incdir', which is not" >&2
         echo "  .../${stdenv.hostPlatform.config}/include." >&2
         echo "  This library must compile against ITS OWN machine's tm.h." >&2
         echo "  A sibling build directory or another target's directory would" >&2
         echo "  both satisfy configure's own check, and both produce a" >&2
         echo "  libgcc.a for the wrong machine under the right file names." >&2
         exit 1 ;;
    esac
    echo "libgcc: generated headers from $incdir"
  '';

  # `--build` and `--host` ONLY. No `--target`: this is one machine's library,
  # and `--host` is that machine.
  configurePlatforms = [
    "build"
    "host"
  ];

  configureFlags = [
    "--disable-dependency-tracking"
    "gcc_cv_target_thread_file=${threadModel}"
    # $CC cannot link binaries, let alone run them
    "cross_compiling=true"
    "--enable-static"

    (lib.enableFeature enableShared "shared")
  ];

  # NO `inhibit_libc=`. It used to be stated here because `gcc/configure`
  # decided it and handed it over in `libgcc.mvars`, and a native build of the
  # pre-libc stage would have come out `false`. libgcc now PROBES it
  # (`configure.ac:318-330`), by compiling `#include <stdio.h>` against the
  # headers these objects will actually use -- which is a better answer than
  # either of us can state, since it is about the compiler this build was
  # handed. The `postInstall` symbol assertions are what make that checkable.

  # NO `MULTIBUILDTOP`. It is the top level's variable for telling an in-tree
  # target library how deep multilib put it, so relative paths still reach
  # `gcc/`. Nothing here is in a tree.
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

    # THE `dl_iterate_phdr` FDE LOOKUP, WHICH IS A DIFFERENT DEFECT WITH THE
    # SAME SIGNATURE AND HAS TO BE ASKED SEPARATELY.
    #
    # `inhibit_libc` drops it, and so does a failed `HAVE_LD_EH_FRAME_HDR` --
    # and that probe fails whenever `gcc/configure` could not RUN the target
    # linker, because a probe it cannot run records "no". Either way
    # `unwind-dw2-fde-dip.c` compiles with `USE_PT_GNU_EH_FRAME` undefined,
    # leaving only the `__register_frame` registry, which nothing populates for
    # normally linked objects. libgcc and libstdc++ then build, link and install
    # perfectly cleanly under the same file names, and every C++ `throw` finds
    # no FDE and calls `std::terminate`.
    #
    # It is decidable from the archive: with the lookup compiled in,
    # `dl_iterate_phdr` is an UNDEFINED symbol of `unwind-dw2-fde-dip.o`. So ask
    # the undefined set, not the defined one -- the counting function above
    # would report zero for a good build.
    "''${NM:-nm}" --undefined-only "$libgcc_a" > libgcc-undef.txt
    ndip=$(grep -c 'dl_iterate_phdr' libgcc-undef.txt || true)

    # Reported, not asserted: split-stack exists only where the back end builds
    # `generic-morestack.c` (i386 and a few others), so zero is the correct
    # answer on most targets and an assertion on it would fire for the wrong
    # reason. `__gcov_*` is the one libgcov builds everywhere.
    echo "libgcc: __gcov_* = $ngcov, __splitstack_* = $nsplit (reported only)," \
         "dl_iterate_phdr = $ndip"
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
        # The control for the unwinder half, and it is the reason the assertion
        # on the other arm means something. `inhibit_libc` also drops the
        # `dl_iterate_phdr` lookup, so this build MUST NOT have it. If it did,
        # `ndip -ne 0` would be true of every build and the with-libc check
        # could not fail.
        if [ "$ndip" -ne 0 ]; then
          echo "libgcc: built with inhibit_libc=true, yet libgcc.a references" >&2
          echo "libgcc: dl_iterate_phdr $ndip time(s). Either inhibit_libc did" >&2
          echo "libgcc: not take effect, or this probe answers yes regardless" >&2
          echo "libgcc: -- and in that case the check on the with-libc build" >&2
          echo "libgcc: is measuring nothing." >&2
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
      # THE UNWINDER ASSERTION, ELF ONLY. `USE_PT_GNU_EH_FRAME` is an ELF
      # mechanism: `PT_GNU_EH_FRAME` is an ELF program header and
      # `dl_iterate_phdr` is the ELF loader's interface. A PE/COFF or Mach-O
      # target finds its FDEs another way, so requiring the symbol there would
      # fail for the wrong reason -- which is how a real check gets deleted.
      + lib.optionalString stdenv.hostPlatform.isElf ''
        if [ "$ndip" -eq 0 ]; then
          echo "libgcc: this is an ELF target with a real libc, so the" >&2
          echo "libgcc: dl_iterate_phdr FDE lookup must be compiled in -- but" >&2
          echo "libgcc: libgcc.a references dl_iterate_phdr 0 times." >&2
          echo "libgcc:" >&2
          echo "libgcc: USE_PT_GNU_EH_FRAME is off, so unwind-dw2-fde-dip.c" >&2
          echo "libgcc: built with only the __register_frame registry, which" >&2
          echo "libgcc: nothing populates for normally linked objects. This" >&2
          echo "libgcc: library installs under exactly the same file names as" >&2
          echo "libgcc: a good one and every C++ throw will call std::terminate." >&2
          echo "libgcc:" >&2
          echo "libgcc: The usual cause is not inhibit_libc but a configure" >&2
          echo "libgcc: that could not RUN the target linker: HAVE_LD_EH_FRAME_HDR" >&2
          echo "libgcc: then reads no, exactly as a real no would." >&2
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
