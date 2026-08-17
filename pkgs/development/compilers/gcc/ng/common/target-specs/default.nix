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
# tools are there by construction; `postConfigure` reads back WHICH tools were
# chosen, so that is checked rather than assumed.
#
# ==========================================================================
# WHAT THIS DERIVATION PASSES, CLASSIFIED. Nine flags, and the split is the
# point: it says how much of the "fancy pre-configure" is this derivation doing
# work the component should do for itself.
#
#   (a) RE-DERIVED FROM `gcc-unwrapped`'S OUTPUT -- 3, and all three are the
#       defect in nix form. This derivation opens `multi-target.manifest`, so it
#       has to know that file's location, its line format and its key names:
#         `--with-cpu-type`       `awk`ed out of the manifest
#         `--with-option-defaults` `awk`ed out of the manifest
#         `--with-source-specs`   two files sitting BESIDE the manifest
#       Between them they are the whole of `preConfigure`'s 56 lines bar three.
#
#   (b) PROBED FROM THIS TARGET'S TOOLCHAIN -- **0**. Nothing measured is passed
#       IN; the probing is the component's own job and it does all of it. That
#       is the half of the boundary that is already right, and it is worth
#       stating as a count rather than an absence.
#
#   (c) GENUINE nixpkgs-SIDE CHOICES -- 6:
#         `--build` / `--host`    from `configurePlatforms`
#         `--with-target`         nixpkgs' SPELLING of the triple; see below
#         `--with-tools-dir`      which toolchain to probe
#         `--with-specs-file`     where the artefact goes
#         (`--with-native-system-header-dir` WAS here and is gone; see below)
#         (`--with-fixed-include-dir` is a seventh, conditional, and also (c))
#
# `--with-target` IS NOT REDUNDANT WITH `--host`, WHICH IT LOOKS LIKE. Both are
# `stdenv.hostPlatform.config`, so it reads as saying the same thing twice --
# but `--host` goes through `config.sub` and `--with-target` does not, and for
# at least one nixpkgs triple those differ:
#
#     ./config.sub s390x-unknown-linux-gnu  ->  s390x-ibm-linux-gnu
#
# The driver looks up `<version>/<target>/specs-config` under the triple it
# calls ITSELF, which is nixpkgs' spelling. Without `--with-target` the file
# would be written under the canonical one and never found -- one name, two
# authorities, and the failure would be `no configuration file for target`
# pointing at a path that exists under a different name.
# ==========================================================================
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
    # `mlib-specs-<target>` is genuinely optional -- `gen-multilib-specs.sh` can
    # fail for a target with no multilib tables, and `multi-target-specs` reports
    # that and carries on -- so a missing one must not stop this. But the
    # `test -f "$f" && ...` this used to be is a compound that RETURNS 1 when the
    # file is absent, and under `set -e` a failing last statement in a loop body
    # aborts the phase with no message at all. It never fired because all 48
    # targets in this compiler happen to have both files; that is a property of
    # today's tree, not of the code.
    sourceSpecs=
    for f in "${srcSpecsDir}/specs-src-${target}" "${srcSpecsDir}/mlib-specs-${target}"; do
      if test -f "$f"; then sourceSpecs="$sourceSpecs $f"; fi
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
    #
    # WHAT IS ACTUALLY IN `bintools` TODAY: `buildPackages.binutilsNoLibc`, a
    # wrapper that runs on the build machine and emits for this target. The
    # `NoLibc` is a cycle break, not a capability statement -- the call site in
    # `../default.nix` records the three candidates that recursed, and records
    # that the with-libc and no-libc wrappers produce byte-identical
    # `specs-config`.
    "--with-tools-dir=${bintools}/bin"

    # `collect2` NEEDS ABSOLUTE PATHS, AND THIS SCRIPT WILL NOT GUESS THEM.
    #
    # `--with-tools-dir` above governs PROBING; these govern what the finished
    # compiler RUNS. `REAL_{LD,NM,STRIP}_FILE_NAME` used to be compiled into
    # `collect2` from gcc's configure -- one machine's answer for every target --
    # and on this branch they are per-target keys of `specs-config` instead.
    #
    # They are emitted ONLY if named here: `target-specs/configure.ac:476-505`
    # leaves `ts_emit_real_tools=no` unless one of `--with-real-{ld,nm,strip}`
    # is passed, and the comment above them says why it is not probed -- "a
    # probe would have to decide that some ld it found on PATH is *this
    # target's real ld*, which is exactly the guess that put the host's tools in
    # front of every target in the first place."
    #
    # So this is not a workaround; it is supplying an input the component asks
    # for by name and deliberately declines to infer. nixpkgs is the one party
    # that knows the answer without guessing: it is the same wrapped bintools
    # already named above, and the prefix comes from that package rather than
    # being spelled again here.
    #
    # MEASURED CONSEQUENCE OF OMITTING THEM: `libgcc` compiles every object and
    # then dies linking the shared library with
    #
    #     collect2: fatal error: cannot find 'ld'
    #
    # -- `collect2` asking for the UNPREFIXED name, with only
    # `<triple>-ld` on PATH. `libgcc.a` is unaffected, so the failure appears
    # only at `libgcc_s.so` and looks like a linker problem rather than a
    # missing capability key.
    "--with-real-ld=${bintools}/bin/${bintools.targetPrefix}ld"
    "--with-real-nm=${bintools}/bin/${bintools.targetPrefix}nm"
    "--with-real-strip=${bintools}/bin/${bintools.targetPrefix}strip"

    "--with-specs-file=${placeholder "out"}/${specsDir}/specs"
  ]
  # NO `--with-native-system-header-dir`, AND ITS REMOVAL IS THE FIX FOR #256.
  #
  # It used to be here, guarded by `stdenv.cc.libc != null`, and it was the last
  # structural cycle in the chain:
  #
  #   musl -> stdenvNoLibc -> gccWithLibgcc -> gcc-composed -> target-specs
  #        -> stdenv.cc.libc -> musl
  #
  # THE STAGE SELECTION WAS NEVER WRONG, which is worth saying because the
  # trace points at the wrapper and invites that conclusion. `musl`'s package
  # takes `stdenvNoLibc` for a cross build (`by-name/mu/musl/package.nix:10`),
  # and `all-packages.nix:104-108` gives that `gccWithLibgcc`, whose
  # `binutilsNoLibc` is the designed pre-libc break. That is all correct. The
  # cycle re-entered one level DOWN, through the compiler this file composes:
  # `gcc-composed` needs `target-specs`, and `target-specs` was reading the
  # libc off the very stdenv that was waiting for it.
  #
  # NOTHING ABOUT THE FIX IS MUSL-SPECIFIC. Any libc built by a gcc-ng stdenv
  # closes the same loop; musl is only where a `useGccNG` cross was first
  # evaluated. So it is fixed where the dependency was created rather than by
  # special-casing a libc.
  #
  # AND THE LINE SHOULD NOT HAVE BEEN HERE ANYWAY. `../gcc` refuses
  # `--with-sysroot` and `--with-native-system-header-dir` in as many words --
  # "would make every libc change rebuild the compiler, precisely the coupling
  # this split package set exists to remove" -- and this re-introduced exactly
  # that coupling one component down, where it makes `gcc-composed`, and so
  # every wrapper, a function of the libc. It was also a second authority for a
  # path cc-wrapper already supplies as `-idirafter <libc.dev>/include`.
  #
  # What changes in the artefact: `specs-config`'s `native_system_header_dir`
  # key becomes empty rather than naming a store path. cc1 drops an empty entry
  # from the include chain, which is the honest answer -- this compiler is not
  # built against a libc, and the wrapper that composes a target is what knows
  # which one.
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

  # WHICH ASSEMBLER AND LINKER WERE ACTUALLY PROBED. The comment at the top of
  # this file says the failure to fear is a spec file that NAMES this target
  # while DESCRIBING the build machine, and until now nothing here could tell
  # the difference: `installPhase` checked that a file appeared, and a file
  # appears either way.
  #
  # `config.log` records the answer -- `result: aarch64-unknown-linux-gnu-as`
  # where a fallback would say `result: as` -- so read it back.
  #
  # The test is not "is it prefixed", which would be wrong for a native target
  # where the unprefixed name is the only one that exists. It is "does the
  # directory we told it to use actually provide a tool by that name". That is
  # right on both: a cross bintools wrapper installs ONLY `<triple>-as`, so a
  # fallback to plain `as` fails this; a native one installs `as`, so the
  # correct native answer passes.
  #
  # Every step refuses to be silent. A missing `config.log`, a `checking` line
  # that is not there, and an empty result are three different ways to get "no
  # evidence", and none of them may read as "evidence of success".
  postConfigure = ''
    test -f config.log || {
      echo "target-specs: no config.log, so which tools were probed cannot be" >&2
      echo "  established. Refusing to accept the spec file on trust." >&2
      exit 1; }

    tsProbed() {
      awk -v want="checking for a usable $1" '
        index($0, want) { getline; sub(/^configure:[0-9]*: result: /, ""); print; exit }
      ' config.log
    }

    for tool in assembler linker; do
      got=$(tsProbed "$tool")
      test -n "$got" || {
        echo "target-specs: config.log has no result for \`a usable $tool'." >&2
        echo "  Either configure stopped before that check or its message" >&2
        echo "  changed. Either way this check is reading nothing, which must" >&2
        echo "  not pass." >&2
        exit 1; }
      test "$got" != "not found" || {
        echo "target-specs: configure found no usable $tool for ${target}." >&2
        exit 1; }
      test -x "${bintools}/bin/$got" || {
        echo "target-specs: ${target}'s $tool was probed as \`$got', which" >&2
        echo "  ${bintools}/bin does not provide." >&2
        echo "  That is the documented failure: configure fell back to a tool" >&2
        echo "  found elsewhere on PATH -- the BUILD machine's, in a cross" >&2
        echo "  build -- and would write a spec file naming ${target} while" >&2
        echo "  describing that machine, with every path- and name-based check" >&2
        echo "  still green." >&2
        exit 1; }
      echo "target-specs: ${target}: $tool = $got (from ${bintools}/bin)"
    done
  '';

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

    # `test -f` above is satisfied by an EMPTY file, so count the keys and
    # require some. The `|| true` here is only so that `grep -c` returning 1 on
    # no match does not abort before the count can be reported; zero is then an
    # error with a name, rather than a number printed on the way past.
    nkeys=$(grep -c '^[a-z_]' "$out/${specsDir}/specs-config" || true)
    test "$nkeys" -gt 0 || {
      echo "target-specs: $out/${specsDir}/specs-config has no capability keys." >&2
      echo "  configure's own reader/expected-list comparison should have made" >&2
      echo "  this impossible, so an empty file here means that check did not" >&2
      echo "  run -- which is worth failing on rather than shipping." >&2
      exit 1; }
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
