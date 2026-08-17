{
  lib,
  stdenvNoCC,
  stdenv,
  gcc_meta,
  release_version,
  version,
  monorepoSrc ? null,
  fixincludes,
  gcc-unwrapped,
  # A compiler that can preprocess for this target. `mkheaders` needs the set of
  # macros the preprocessor predefines and refuses to run without it; see below.
  cc,
}:
# ONE TARGET'S FIXED SYSTEM HEADERS. Thin, and per target, which is the whole
# distinction: `../fixincludes` BUILDS the fixer once per host, and this RUNS it
# once per target. Same split as `gcc-unwrapped` (back ends) versus the wrapper
# (targets).
#
# WHAT IT IS A FUNCTION OF, MEASURED FROM `fixincludes/mkheaders.in` RATHER THAN
# ASSUMED, because "one derivation per triple" would have been wrong:
#
#   `--target=TRIPLE` (`:85`, required at `:112`) -- passed to `fixincl` as
#       `TARGET_MACHINE`, which fnmatches it against each hack's `mach` glob at
#       RUN time. 137 of 252 hacks carry one. No default: an empty value puts
#       `fixincl` into its self-test mode, where gating is off and EVERY
#       machine's fixes apply.
#   `--headers=DIR` (`:86`, required at `:120`) -- that machine's system header
#       directory. It is an ARGUMENT, not something baked in at
#       `../fixincludes` configure time; the comment at `:38` says it used to be
#       `SYSTEM_HEADER_DIR` in `mkheaders.conf`, i.e. one target's answer
#       written down as everyone's, and that this is why it moved. So two
#       targets with the same triple and different libcs are two different
#       inputs here and cannot collide on one store path.
#   `--gcc=CMD` or `--macro-list=FILE` (`:204-227`) -- the macros the
#       preprocessor predefines for this target. Also no default, and for a
#       stated reason: an empty list reads as "nothing is predefined" and
#       changes which fixes fire, which is how gcc's old rule shipped an empty
#       one at exit 0.
#
# AND WHAT IT READS THAT IS NOT AN ARGUMENT, which is where the awkwardness is:
#
#   `${itoolsdatadir}/fixinc_list`, `gsyslimits.h` and `include*/limits.h`
#       (`:167`, `:243`, `:246`) come from GCC's `install-mkheaders`, i.e. from
#       the `gcc` derivation, under `<libdir>/gcc/<version>/install-tools`.
#   `${itoolsdir}/mkinstalldirs` (`:165`) ALSO comes from `install-mkheaders`
#       (`gcc/Makefile.in:6898`), while `mkheaders`, `fixinc.sh` and `fixincl`
#       come from `fixincludes`' own `install`. Two components install into one
#       directory, deliberately -- `fixincludes/Makefile.in:230` has a comment
#       explaining that the `rm -rf` that used to be there made the result
#       depend on which ran last.
#
# In an installation those two halves land in the same tree and the split is
# invisible. Here they are two store paths, and neither is writable, while
# `mkheaders` does `cd ${itoolsdir}` and writes `macro_list` into its working
# directory. So this derivation assembles a writable `install-tools` from both,
# which is not a workaround for nix: it is the same assembly a `make install`
# performs, done explicitly.
#
# THE ONE PLACE THAT REALLY DOES NEED CHANGING IS THE OUTPUT PATH.
# `mkheaders.in:147-155` takes `libdir` and `libexecdir` from `@libdir@` and
# `@libexecdir@`, substituted when `../fixincludes` was configured, and computes
# `incdir=${libdir}/gcc/${version}/${target}/include-fixed` from them. The
# `prefix` positional argument at `:129` is read and then used for none of it.
# So `mkheaders` can only ever write into `../fixincludes`' own store path.
# `sed` on the copied script is the honest minimum; the real fix is for
# `mkheaders` to honour its own `prefix` argument.
let
  target = stdenv.hostPlatform.config;
  libc = stdenv.cc.libc or null;

  itools = "libexec/gcc/${release_version}/install-tools";
  itoolsData = "lib/gcc/${release_version}/install-tools";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "gcc-include-fixed";
  inherit version;

  src = monorepoSrc;

  strictDeps = true;

  nativeBuildInputs = [ cc ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    # Both halves of `install-tools`, in one writable tree, as an installation
    # would have them.
    mkdir -p "$NIX_BUILD_TOP/it/${itools}" "$NIX_BUILD_TOP/it/${itoolsData}"
    cp -r "${fixincludes}/${itools}/." "$NIX_BUILD_TOP/it/${itools}/"
    cp -r "${gcc-unwrapped}/${itoolsData}/." "$NIX_BUILD_TOP/it/${itoolsData}/"
    chmod -R u+w "$NIX_BUILD_TOP/it"

    # Name the file whose absence `mkheaders` reports as its own error, so that
    # "gcc did not run install-mkheaders" and "mkheaders is broken" do not look
    # alike.
    test -f "$NIX_BUILD_TOP/it/${itoolsData}/fixinc_list" || {
      echo "include-fixed: ${gcc-unwrapped} has no ${itoolsData}/fixinc_list." >&2
      echo "  That file comes from gcc's \`install-mkheaders'. Without it" >&2
      echo "  mkheaders has no multilib list to loop over." >&2
      exit 1; }
    test -f "$NIX_BUILD_TOP/it/${itools}/mkinstalldirs" || {
      echo "include-fixed: no mkinstalldirs in ${itools}." >&2
      echo "  It is installed by gcc's \`install-mkheaders', not by" >&2
      echo "  fixincludes, and mkheaders fails without it." >&2
      exit 1; }

    # THIS TARGET'S `fixinc.sh`, NOT THE HOST'S. `fixincludes` had to choose one
    # at build time (`Makefile.in:178`), and `mkfixinc.sh` writes a two-line
    # `exit 0` no-op for cygwin, mingw, vxworks7, several powerpc embedded
    # targets and every musl target. Regenerate it for the target actually being
    # fixed; see the note in `../fixincludes`.
    ( cd "$NIX_BUILD_TOP/it/${itools}" \
      && srcdir="$NIX_BUILD_TOP/it/${itools}" sh ./mkfixinc.sh ${target} )
    echo "include-fixed: ${target}'s fixinc.sh is" \
         "$(wc -c < "$NIX_BUILD_TOP/it/${itools}/fixinc.sh") bytes"

    # Point `mkheaders` at a prefix it can write to. See the note above: its
    # `prefix` argument does not reach `libdir`, so the substituted values are
    # rewritten instead. Both directions are checked, because a `sed` that
    # matched nothing leaves a script that writes into the store, fails, and
    # blames the store.
    mk="$NIX_BUILD_TOP/it/${itools}/mkheaders"
    grep -q '^libdir=' "$mk"
    sed -i \
      -e "s|^libdir=.*|libdir=$NIX_BUILD_TOP/it/lib|" \
      -e "s|^libexecdir=.*|libexecdir=$NIX_BUILD_TOP/it/libexec|" \
      "$mk"
    grep -q "^libdir=$NIX_BUILD_TOP/it/lib\$" "$mk"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    sh "$NIX_BUILD_TOP/it/${itools}/mkheaders" \
      --target=${target} \
      --headers=${lib.getDev libc}/include \
      --gcc="${lib.getExe' cc "${stdenv.cc.targetPrefix}cc"}"

    src="$NIX_BUILD_TOP/it/lib/gcc/${release_version}/${target}/include-fixed"

    # `mkheaders` writes nothing and exits 0 when the fixer is the no-op one, so
    # an empty directory and a missing one both have to be told apart from a
    # real result. Report the count; do not assert on it, because a target whose
    # headers need no fixing genuinely produces few files -- but make the number
    # visible so that a silent zero is a number someone can see.
    test -d "$src" || {
      echo "include-fixed: mkheaders wrote no $src at all." >&2
      exit 1; }
    n=$(find "$src" -type f | wc -l)
    echo "include-fixed: ${target}: $n fixed header(s)"

    mkdir -p "$out/lib/gcc/${release_version}/${target}"
    cp -r "$src" "$out/lib/gcc/${release_version}/${target}/include-fixed"

    runHook postInstall
  '';

  passthru = {
    inherit target;
    # The path inside `out` that `target-specs` should be given as
    # `--with-fixed-include-dir`. Relative, because an absolute one would have
    # to be `placeholder "out"`, which is only meaningful inside this
    # derivation's own attributes.
    includeSubdir = "lib/gcc/${release_version}/${target}/include-fixed";
  };

  meta = gcc_meta // {
    homepage = "https://gcc.gnu.org/";
    description = "One target's fixincludes-processed system headers";
  };
})
