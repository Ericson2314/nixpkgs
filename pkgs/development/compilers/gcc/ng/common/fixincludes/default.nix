{
  lib,
  stdenv,
  gcc_meta,
  release_version,
  version,
  monorepoSrc ? null,
  libiberty,
}:
# THE HOST HALF OF fixincludes. It builds `fixincl`, `fixinc.sh` and
# `mkheaders`, and it has a `--host` and no target.
#
# That is the component's own claim, not an inference: `fixincludes/configure.ac`
# says so where `ACX_NONCANONICAL_TARGET` used to be -- `libsubdir` is
# `$(libdir)/gcc/$(gcc_version)` with no triple in it, and `Makefile.def` lists
# `fixincludes` under `build_modules` and `host_modules` and never under
# `target_modules`, so GCC's own build system has never configured it per
# target. The target enters one level down, as an ARGUMENT to `mkheaders`; see
# `../include-fixed`, which is the per-target half.
#
# ONE PER-TARGET DECISION IS STILL MADE HERE, AND IT IS A DEFECT WORTH NAMING.
# `fixincludes/Makefile.in:178` is
#
#     srcdir="$(srcdir)" $(SHELL) $(srcdir)/mkfixinc.sh $(target)
#
# and `mkfixinc.sh` chooses between the real fixer and a two-line `exit 0`
# no-op, from a `case` on the triple that lists cygwin, mingw, several powerpc
# embedded targets, vxworks7 and **every musl target**. So a `fixinc.sh` built
# once for one target is one target's answer standing in for everyone's -- and
# it fails in the quiet direction, because the no-op fixer exits 0 and yields an
# empty `include-fixed` that looks exactly like a target with nothing to fix.
#
# This derivation therefore installs the raw ingredients as well, and
# `../include-fixed` re-runs `mkfixinc.sh` for ITS target. The real fix is to
# move that decision to run time, next to the rest of what `mkheaders` already
# decides per target; that is a change to `Makefile.in:178` and `mkheaders.in`,
# not to this file.
stdenv.mkDerivation (finalAttrs: {
  pname = "fixincludes";
  inherit version;

  src = monorepoSrc;

  strictDeps = true;

  postUnpack = ''
    mkdir -p ./build
    buildRoot=$(readlink -e "./build")
  '';

  postPatch = ''
    sourceRoot=$(readlink -e "./fixincludes")
  '';

  enableParallelBuilding = true;

  # THE BOUNDARY, ENUMERATED, exactly as in `../gcc`. Building `fixincludes/`
  # alone with nothing beside it fails on one file, named by `make` itself:
  # `../libiberty/libiberty.a` (`fixincludes/Makefile.in:136`). That is the
  # whole of what this component wants from a sibling build directory, and it is
  # a derivation here.
  preConfigure = ''
    mkdir -p "$buildRoot/libiberty"
    install -m644 "${libiberty}/lib/libiberty.a" "$buildRoot/libiberty/libiberty.a"

    mkdir -p "$buildRoot/fixincludes"
    cd "$buildRoot/fixincludes"
    configureScript=$sourceRoot/configure
    chmod +x "$configureScript"
  '';

  configurePlatforms = [
    "build"
    "host"
  ];

  configureFlags = [
    "--disable-dependency-tracking"
  ];

  # `mkheaders` bakes `@libdir@` and `@libexecdir@` in, and computes
  # `libsubdir=${libdir}/gcc/${version}` from them
  # (`fixincludes/mkheaders.in:147-155`). Its `prefix` positional argument is
  # read and then never used for any of that, so this prefix is where every
  # `mkheaders` run will try to WRITE, not merely where it reads from. The
  # per-target derivation copies and rewrites rather than pointing at a store
  # path it cannot write to; see `../include-fixed`.
  postInstall = ''
    itools="$out/libexec/gcc/${release_version}/install-tools"

    # `make install` writes four files here and reports success if it writes
    # none of them -- the rule used to abort on its first line and did so
    # silently for years (see the comment at `fixincludes/Makefile.in:40`). So
    # name them.
    for f in fixincl fixinc.sh mkheaders; do
      test -f "$itools/$f" || { echo "fixincludes: $itools/$f was not installed" >&2; exit 1; }
    done

    # The ingredients for a per-target `fixinc.sh`, because the one installed
    # above is this derivation's target's answer. See the note at the top.
    install -m644 "$sourceRoot/fixinc.in" "$itools/fixinc.in"
    install -m755 "$sourceRoot/mkfixinc.sh" "$itools/mkfixinc.sh"

    # A one-line `exit 0` is what `mkfixinc.sh` writes for a target that needs
    # no fixing, and it is also what a broken build would leave. They are
    # distinguishable only by size, so record which one this is rather than
    # leaving the next reader to guess.
    echo "fixincludes: installed fixinc.sh is $(wc -c < "$itools/fixinc.sh") bytes" \
         "for target ${stdenv.hostPlatform.config}"
  '';

  passthru = {
    # Where `../include-fixed` looks. Written down once, here, rather than
    # recomputed at each use site.
    itoolsSubdir = "libexec/gcc/${release_version}/install-tools";
  };

  meta = gcc_meta // {
    homepage = "https://gcc.gnu.org/";
    description = "GCC's system-header fixer, host half";
  };
})
