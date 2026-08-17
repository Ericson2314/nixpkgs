{
  lib,
  stdenvNoCC,
  stdenv,
  gcc_meta,
  release_version,
  version,
  fixincludes,
  gcc-unwrapped,
  # NOTE: the compiler comes from `stdenv.cc`, not as an argument -- see below.
}:
# ONE TARGET'S FIXED SYSTEM HEADERS. Thin, and per target, which is the whole
# distinction: `../fixincludes` BUILDS the fixer once per host, and this RUNS it
# once per target. Same split as `gcc-unwrapped` (back ends) versus the target.
#
# WHAT IT IS A FUNCTION OF, MEASURED FROM `fixincludes/mkheaders.in` RATHER THAN
# ASSUMED, because "one derivation per triple" would have been wrong. Every one
# of these is an option with NO default, and each fails by name:
#
#   `--target=TRIPLE` -- passed to `fixincl` as `TARGET_MACHINE`, which
#       fnmatches it against each hack's `mach` glob at RUN time; 137 of 252
#       hacks carry one. An empty value puts `fixincl` into its self-test mode,
#       where gating is off and EVERY machine's fixes apply.
#   `--headers=DIR` -- that machine's system header directory. An ARGUMENT, not
#       something baked in when `../fixincludes` was configured: it used to be
#       `SYSTEM_HEADER_DIR` in `mkheaders.conf`, i.e. one target's answer
#       written down as everyone's. So two targets with the same triple and
#       different libcs are different inputs here and cannot collide on one
#       store path.
#   `--gcc=CMD` (or `--macro-list=FILE`) -- the macros the preprocessor
#       predefines for this target. An empty list reads as "nothing is
#       predefined" and changes which fixes fire, which is how gcc's old rule
#       shipped an empty one at exit 0.
#   `--itoolsdatadir=DIR` -- REQUIRED, and see below; it cannot be derived.
#   `--incdir=DIR` -- REQUIRED, THE OUTPUT. Also `rm -rf`'d before it is
#       written, so `mkheaders` refuses a relative path or one with fewer than
#       three components before doing that.
#
# `--itoolsdir` is NOT passed: `mkheaders` self-locates by `dirname $0`, which
# is right wherever it was installed, store path included, and cannot disagree
# with reality the way a configure-time answer could.
#
# THE ONE THING STILL SHARED WITH `gcc`, AND IT IS NOT `mkinstalldirs` ANY MORE.
# `fixincludes` now installs `mkinstalldirs` into its own tool directory, so
# `itoolsdir` has a single producer and this derivation runs it straight out of
# that store path. But `--itoolsdatadir` is a different tree, and its three
# files -- `fixinc_list`, `gsyslimits.h` and `include*/limits.h` -- are still
# written by gcc's `install-mkheaders` (`gcc/Makefile.in:6889`); `fixincludes`
# installs only a `README` there. `mkheaders`' own `--itoolsdatadir` help text
# says as much ("installed by gcc's `install-mkheaders'"). So the dependency on
# `gcc` is REDUCED, not removed, and it is now for data rather than for a shell
# script -- which is a fair boundary: that data is per-multilib and gcc is what
# knows the multilibs.
#
# `itoolsdir` IS STILL COPIED, FOR ONE REASON THAT IS NOT ABOUT WRITABILITY.
# `fixincludes/Makefile.in` builds `fixinc.sh` with `mkfixinc.sh $(target)`, and
# that script chooses between the real fixer and a two-line `exit 0` from a
# `case` on the triple listing cygwin, mingw, vxworks7, several powerpc embedded
# targets and **every musl target**. Built once per host, that is one target's
# answer standing in for everyone's, and it fails in the quiet direction: the
# no-op exits 0 and yields an empty `include-fixed` indistinguishable from a
# target with nothing to fix. So the tool directory is copied and `fixinc.sh` is
# regenerated for the target actually being fixed. The real fix is to move that
# decision to run time, beside everything else `mkheaders` already decides per
# target; that is `Makefile.in:178`, not this file.
#
# Having a writable copy also means `mkheaders` can build `macro_list` itself --
# it writes it into `pwd` after `cd ${itoolsdir}` -- so `--gcc=` is passed
# rather than `--macro-list=`, and the "refuse an empty list" check stays in the
# one place that owns it.
let
  target = stdenv.hostPlatform.config;
  libc = stdenv.cc.libc or null;

  # Read back from the producer rather than respelled. `../fixincludes` bound
  # these when it ran `make install bindir=... datadir=...`, and gcc's
  # `install-mkheaders` uses the same `lib/gcc/<version>/install-tools` for its
  # half.
  inherit (fixincludes) itoolsSubdir itoolsDataSubdir;

  incdir = "lib/gcc/${release_version}/${target}/include-fixed";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "gcc-include-fixed";
  inherit version;

  dontUnpack = true;
  dontConfigure = true;
  strictDeps = true;

  # `stdenv.cc` is the compiler that RUNS on the build machine and serves this
  # derivation's platform -- the same authority `../libgcc` reads.
  nativeBuildInputs = [ stdenv.cc ];

  buildPhase = ''
    runHook preBuild

    # `fixinc_list` is gcc's, and its absence has two very different causes --
    # "gcc did not run install-mkheaders" and "mkheaders is broken" -- which
    # look identical from the failure. Name this one.
    test -f "${gcc-unwrapped}/${itoolsDataSubdir}/fixinc_list" || {
      echo "include-fixed: ${gcc-unwrapped} has no ${itoolsDataSubdir}/fixinc_list." >&2
      echo "  That file is gcc's \`install-mkheaders'. Without it mkheaders has" >&2
      echo "  no multilib list to loop over, and fixing only the top-level" >&2
      echo "  directory leaves every non-default multilib unfixed, silently." >&2
      exit 1; }

    # A writable tool directory. Note it is `fixincludes`' alone now:
    # `mkinstalldirs` comes with it, so there is no second half to merge in.
    it="$NIX_BUILD_TOP/itools"
    mkdir -p "$it"
    cp -r "${fixincludes}/${itoolsSubdir}/." "$it/"
    chmod -R u+w "$it"

    for f in fixincl fixinc.sh mkheaders mkinstalldirs; do
      test -f "$it/$f" || {
        echo "include-fixed: ${fixincludes} has no ${itoolsSubdir}/$f." >&2
        exit 1; }
    done

    # THIS TARGET'S `fixinc.sh`, NOT THE HOST'S -- see the note at the top.
    hostSize=$(wc -c < "$it/fixinc.sh")
    ( cd "$it" && srcdir="$it" sh ./mkfixinc.sh ${target} )
    echo "include-fixed: fixinc.sh was $hostSize bytes for the host," \
         "$(wc -c < "$it/fixinc.sh") bytes for ${target}"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/${incdir}"

    # `--itoolsdir` is deliberately absent: `mkheaders` self-locates by
    # `dirname $0`, so running the copy is what selects the copy.
    sh "$it/mkheaders" \
      --target=${target} \
      --headers=${lib.getDev libc}/include \
      --gcc="${lib.getExe' stdenv.cc "${stdenv.cc.targetPrefix}cc"}" \
      --itoolsdatadir=${gcc-unwrapped}/${itoolsDataSubdir} \
      --incdir="$out/${incdir}"

    # `mkheaders` writes nothing and exits 0 when `mkfixinc.sh` handed it the
    # no-op fixer, so an empty directory and a real result are the same exit
    # status. Report the count; do not assert a threshold on it, because a
    # target whose headers need no fixing genuinely produces few files -- but
    # make the number visible so a silent zero is a number someone can see.
    n=$(find "$out/${incdir}" -type f | wc -l)
    echo "include-fixed: ${target}: $n fixed header(s) in $out/${incdir}"

    runHook postInstall
  '';

  passthru = {
    inherit target;
    # What `../target-specs` takes as `--with-fixed-include-dir`, relative to
    # this derivation's `out`.
    includeSubdir = incdir;
  };

  meta = gcc_meta // {
    homepage = "https://gcc.gnu.org/";
    description = "One target's fixincludes-processed system headers";
  };
})
