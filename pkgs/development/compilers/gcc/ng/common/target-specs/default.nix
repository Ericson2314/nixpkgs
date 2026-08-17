{
  lib,
  stdenvNoCC,
  stdenv,
  gcc_meta,
  release_version,
  version,
  monorepoSrc ? null,
  gcc-unwrapped,
  # THE BINUTILS THAT RUN ON THE BUILD MACHINE AND EMIT FOR THIS TARGET, i.e.
  # the ones whose `bin` holds `<triple>-as` and `<triple>-ld`.
  #
  # An argument, and the rule is: IT MUST NOT BE REACHED THROUGH ANY COMPILER.
  # Every `stdenv.cc.*` route is a cycle, because on a `useGccNG` platform the
  # stdenv's compiler wraps `../gcc-composed`, which is built from THIS
  # derivation -- so the spec file would depend on a compiler that cannot exist
  # until the spec file does.
  #
  # Nor is it the scope's own `binutils`: in a cross set that is the copy which
  # RUNS on the target, cannot be executed on the builder, and whose own
  # `buildInputs` are target libraries -- the same cycle by a longer route.
  #
  # The call site (`../default.nix`) documents the four candidates that were
  # tried and which three failed, with their errors.
  bintools,
  # This target's fixed system headers, if they have been made. `null` is the
  # honest answer before `mkheaders` has run, and it is NOT the same as "there
  # are none": see the note on `--with-fixed-include-dir` below.
  includeFixed ? null,
}:
# ONE TARGET'S SPEC FILE AND CAPABILITY CONFIG, PROBED FROM THE TOOLCHAIN THAT
# IS ACTUALLY THERE.
#
# This is the derivation that makes a target a thing in the package set.
# `gcc-unwrapped` ships BACK ENDS -- one store path, 47 of them, no target -- and
# every fact that depends on which assembler and linker a target has is asked
# here instead, after the build, by `target-specs/configure`. The rationale is
# in that script's first paragraph: the `HAVE_AS_*`/`HAVE_LD_*` checks are
# probes of a SPECIFIC binary, not properties of a target, so a multi-target
# compiler cannot answer them when it is configured.
#
# WHY THE REAL CROSS BINUTILS ARE NOT OPTIONAL. With the target's assembler
# absent, configure falls back to the build machine's own and writes a file that
# NAMES this target while DESCRIBING x86_64 -- measured upstream at 95 of 101
# lines identical between two such files, with every name- and path-based check
# still green. `--with-tools-dir` below is a wrapped bintools directory, so the
# tools are there by construction; the assertion after configure is what makes
# that checkable rather than assumed.
let
  target = stdenv.hostPlatform.config;

  # The compiler's own per-target layout, and the path this file must end up at
  # for an installed driver to find it: `<libdir>/gcc/<version>/<target>/`
  # (`gcc/gcc.cc:8681`). `$out` is a real prefix, so writing straight there is
  # both locations at once -- the artefact a `make install` user gets and the
  # artefact a wrapper consumes are the same file in the same place, which is
  # the requirement. Note also that `target-specs` embeds absolute paths in the
  # spec file it writes, and `mt-install-config.sh` exists only to rewrite them
  # when a build tree is copied into an installation. Nothing is copied here, so
  # there is nothing to rewrite and no second authority for the path.
  specsDir = "lib/gcc/${release_version}/${target}";

  # gcc's build wrote these; see the `postInstall` in `../gcc`.
  srcSpecsDir = "${gcc-unwrapped}/lib/gcc/${release_version}/multi-target";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "gcc-target-specs";
  inherit version;

  src = monorepoSrc;

  strictDeps = true;

  # NOTHING IS COMPILED HERE, WHICH IS WHY THIS IS `stdenvNoCC`. The script runs
  # the target's assembler and linker on hand-written `.s` files and reads what
  # they say; it never needs a working C compiler for the target, and asking for
  # one would make this depend on `libgcc`, which depends on this.
  nativeBuildInputs = [ bintools ];

  postUnpack = ''
    mkdir -p ./build
    buildRoot=$(readlink -e "./build")
  '';

  postPatch = ''
    sourceRoot=$(readlink -e "./target-specs")
  '';

  dontBuild = true;

  preConfigure = ''
    cd "$buildRoot"
    configureScript=$sourceRoot/configure
    chmod +x "$configureScript"

    mkdir -p "$out/${specsDir}"

    # `--with-cpu-type` and `--with-option-defaults` come out of the manifest
    # gcc's build wrote, and there is no default for either. The top level's
    # rule refuses to run without the manifest for a stated reason
    # (`Makefile.tpl:2424`): probing without it writes an EMPTY
    # `*option_defaults` spec, which is indistinguishable from a target that
    # genuinely has none. Same here -- read it, and fail by name if this target
    # is not in it.
    manifest="${srcSpecsDir}/multi-target.manifest"
    test -f "$manifest" || {
      echo "target-specs: no $manifest." >&2
      echo "  It is written by \`make multi-target-specs' in the gcc build and" >&2
      echo "  installed by that derivation. Without it this script cannot know" >&2
      echo "  ${target}'s cpu_type or option defaults, and would write an empty" >&2
      echo "  answer that reads as a real one." >&2
      exit 1; }

    cpuType=$(awk -v t=${target} \
      '$1 == "target" { seen = ($2 == t) } seen && $1 == "cpu_type" { print $2; exit }' \
      "$manifest")
    test -n "$cpuType" || {
      echo "target-specs: $manifest has no cpu_type for ${target}." >&2
      echo "  Either this compiler does not serve that back end, or the" >&2
      echo "  triple is spelled differently there. Targets in the manifest:" >&2
      awk '$1 == "target" { print "    " $2 }' "$manifest" >&2
      exit 1; }

    optionDefaults=$(awk -v t=${target} \
      '$1 == "target" { seen = ($2 == t) } seen && $1 == "option_defaults" { $1 = ""; print; exit }' \
      "$manifest")

    # The source-derived half. Absent, the spec file still exists, still parses,
    # and the driver silently falls back to generic defaults -- looking for
    # crt0.o where glibc wants crt1.o, with no diagnostic. So require it.
    sourceSpecs=
    for f in "${srcSpecsDir}/specs-src-${target}" "${srcSpecsDir}/mlib-specs-${target}"; do
      test -f "$f" && sourceSpecs="$sourceSpecs $f"
    done
    test -n "$sourceSpecs" || {
      echo "target-specs: no specs-src-${target} in ${srcSpecsDir}." >&2
      echo "  That is the tm.h-derived half of this target's spec file, and" >&2
      echo "  there is no probe that could recover it here." >&2
      exit 1; }

    configureFlagsArray+=(
      "--with-cpu-type=$cpuType"
      "--with-option-defaults=$optionDefaults"
      "--with-source-specs=$sourceSpecs"
    )
  '';

  # `--build` and `--host` only; `--with-target` is what says which machine
  # these specs DESCRIBE, and it is the same triple as the host because this
  # package set instantiates the component once per machine.
  configurePlatforms = [
    "build"
    "host"
  ];

  configureFlags = [
    "--with-target=${target}"

    # Not `--with-as`/`--with-ld`. Two absolute paths are measurably
    # insufficient: several probes invoke OTHER binutils programs, or invoke
    # as/ld in ways that make them exec their siblings, and about ten checks --
    # `HAVE_GAS_CFI_DIRECTIVE`, `HAVE_AS_LEB128`, `HAVE_LD_EH_GC_SECTIONS`
    # among them -- still fail with only those two set. A failed probe is not an
    # error here; it silently records "no". So hand over the whole directory,
    # which is what `--with-tools-dir` is for.
    "--with-tools-dir=${bintools}/bin"

    "--with-specs-file=${placeholder "out"}/${specsDir}/specs"
  ]
  ++ lib.optionals (stdenv.cc.libc or null != null) [
    "--with-native-system-header-dir=${lib.getDev stdenv.cc.libc}/include"
  ]
  # NO `--with-fixed-include-dir` UNLESS THE DIRECTORY EXISTS, AND THE ASYMMETRY
  # IS THE POINT. `mkheaders` ends by saying that nothing searches the fixed
  # headers until this key names them, and cc1's compiled-in default for the key
  # is the empty string, which drops the entry from the include path. So an
  # absent key means "this target has no fixed headers", which is TRUE before
  # `../include-fixed` has run and false afterwards -- naming a directory that
  # does not exist would be the other kind of wrong.
  #
  # This is also where the ordering shows: `../include-fixed` needs a working
  # preprocessor for this target to build its `macro_list`, and that
  # preprocessor needs a spec file, which is this. So the first run of this
  # derivation has `includeFixed = null` and a second, wired through the
  # wrapper, names the result. Two passes, stated rather than hidden.
  ++ lib.optional (includeFixed != null) "--with-fixed-include-dir=${includeFixed}";

  installPhase = ''
    runHook preInstall

    # configure IS the build here, and it has already written into `$out`. What
    # remains is to refuse to believe its exit status.
    #
    # `target-specs/configure` checks its own output thoroughly -- it reads the
    # capability file back and compares the key set against a deliberately
    # duplicated list -- but a configure script that fails and exits 0 is this
    # branch's signature, and the top level's rule says so in as many words
    # (`Makefile.tpl:2478`). So check for the file, not the status.
    for f in specs specs-config; do
      test -f "$out/${specsDir}/$f" || {
        echo "target-specs: configure exited 0 but wrote no $out/${specsDir}/$f" >&2
        exit 1; }
    done

    nkeys=$(grep -c '^[a-z_]' "$out/${specsDir}/specs-config" || true)
    echo "target-specs: ${target}: $nkeys capability keys, $(wc -l < "$out/${specsDir}/specs") spec lines"

    runHook postInstall
  '';

  passthru = {
    inherit target specsDir;
  };

  meta = gcc_meta // {
    homepage = "https://gcc.gnu.org/";
    description = "Per-target spec file and capability config for the multi-target GCC";
  };
})
