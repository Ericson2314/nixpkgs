{
  lib,
  stdenv,
  runCommand,
  gcc_meta,
  release_version,
  version,
  gcc-unwrapped,
  lto-plugin,
  target-specs,
}:
# ONE TARGET, COMPOSED: the target-agnostic compiler and that target's probed
# spec file, in a single prefix.
#
# This is the join the whole design implies -- `gcc-unwrapped` ships back ends,
# `target-specs` ships one target -- and getting it right took three attempts,
# each of which failed in a way worth recording, because two of them look like
# they should work.
#
# THE DRIVER FINDS ITS TARGET'S CONFIG FROM WHERE ITS OWN BINARY REALLY IS.
# `find_target_config` (`gcc/gcc.cc:8694`) searches three roots, in order:
# `$GCC_EXEC_PREFIX`; `make_relative_prefix (argv0, bindir, exec_prefix)`; and
# the configured-in `STANDARD_EXEC_PREFIX`. Under each it looks for
# `<version>/<target>/specs-config`, and it never falls back.
#
#   1. `symlinkJoin` of the two DOES NOT WORK, and the failure is silent about
#      why. The joined prefix does contain
#      `lib/gcc/17.0.0/<target>/specs-config`, but `bin/<target>-gcc` is a
#      symlink into `gcc-unwrapped`, so `make_relative_prefix` resolves to
#      `gcc-unwrapped`'s own prefix and the diagnostic names THAT path -- a
#      store path where the file genuinely is not, while the file sits in the
#      directory the user actually invoked.
#   2. `GCC_EXEC_PREFIX` DOES NOT WORK EITHER, and it fails one step later,
#      which is worse. Pointed at the `target-specs` output it does make the
#      config file be found -- and then `cc1` is not, because that variable is
#      the root for the executable search as well:
#      `fatal error: cannot execute 'cc1'`. One knob, two questions.
#   3. What works is a REAL FILE for the driver in a prefix that also holds the
#      spec file. Everything else may be a symlink; only `argv0` has to resolve
#      inside the composed prefix. Measured: copy the one driver binary, symlink
#      `libexec` and every other `lib/gcc/<version>/` entry, and
#      `<target>-gcc -S` produces correct assembly for the target.
#
# So this copies the drivers and symlinks the rest. It is deliberately not a
# `symlinkJoin`.
let
  # `targetPlatform`, NOT `hostPlatform`. This derivation is a COMPILER: it runs
  # on the host and serves the target, and the spec file it carries is the
  # target's. Reading `hostPlatform` here composed the compiler that runs here
  # with the specs OF the machine it runs on -- so a cross wrapper came out
  # holding x86_64's spec file while its bintools were aarch64's, and the driver
  # said `no configuration file for target aarch64-unknown-linux-gnu' naming two
  # paths under an x86_64 prefix.
  target = stdenv.targetPlatform.config;
in
runCommand "gcc-${target}-${version}"
  {
    inherit target;
    passthru = {
      inherit
        gcc-unwrapped
        target-specs
        target
        ;
      inherit (gcc-unwrapped) langC langCC langObjC langObjCpp langAda langFortran langGo;
      isGNU = true;
    };
    meta = gcc_meta // {
      homepage = "https://gcc.gnu.org/";
      description = "The multi-target GCC composed with ${target}'s probed spec file";
    };
  }
  # WHAT THE SCRIPT BELOW DOES, AND WHY EACH STEP IS THE SHAPE IT IS.
  #
  # 1. THE DRIVERS ARE COPIED, NOT LINKED -- see the note above; this is the
  #    whole mechanism, and a symlink sends the driver looking in
  #    `gcc-unwrapped`'s prefix instead of this one.
  #
  # 2. `libexec/gcc/<version>/` HAS TWO PRODUCERS, so it is merged entry by
  #    entry rather than linked wholesale. `gcc` puts `cc1`, `collect2`,
  #    `lto-wrapper` and `install-tools` there; `../lto-plugin` puts
  #    `liblto_plugin.so` there, because that is where
  #    `find_a_file (&exec_prefixes, LTOPLUGINSONAME)` looks. Symlinking gcc's
  #    whole `libexec` hides the plugin, and the failure is a link error blaming
  #    `lto-wrapper` -- see `../lto-plugin` for why it looks like that.
  #
  # 3. `lib/gcc/<version>/<target>/` HAS TWO PRODUCERS TOO: this target's
  #    `specs` and `specs-config` from `target-specs`, AND its `include/` --
  #    the per-target generated headers (`tconfig.h`, `tm.h`, `options.h`,
  #    `insn-modes.h`, `insn-constants.h`, `auto-host.h`, `version.h`) from
  #    `gcc`'s `install-target-headers`. This used to `ln -s` the whole
  #    `target-specs` directory over the name, which SHADOWS gcc's `include/`.
  #    Nothing would have reported it: the driver still found `specs-config`
  #    and still answered `-dumpspecs`, so the check below passed, and the loss
  #    surfaced one component later as `libgcc`'s configure saying
  #    `<dir>/tm.h does not exist` about a directory that exists and is full of
  #    the wrong thing.
  #
  #    Both merges REFUSE a collision rather than letting merge order decide --
  #    but the refusal is at FILE granularity, via `mergeTree`, and that
  #    distinction was paid for.
  #
  #    It used to refuse on any repeated top-level ENTRY. That is too coarse the
  #    moment two producers legitimately contribute different files to one
  #    directory, which is exactly what `t261` arranged: `target-specs` now
  #    generates `<target>/include/tm.h` and `tm-<triple>.h`, while gcc's
  #    `install-target-headers` still writes the other six into the same
  #    `<target>/include/`. Their FILE sets are disjoint -- `comm -12` is empty
  #    -- yet both supply a directory called `include`, so an entry-level check
  #    reported a collision that did not exist and stopped every build.
  #
  #    `mergeTree` makes real directories all the way down and symlinks only
  #    leaves, so "collision" means what it should: two producers supplying the
  #    same FILE. A genuine clash still fails by name; a shared directory does
  #    not. Note the earlier tm.h double-install WAS a genuine clash and this
  #    still catches it -- the fix narrows the check, it does not weaken it.
  #
  # 4. The two presence checks. `specs-config` is what the driver needs to know
  #    its target at all; `include/tm.h` is what `libgcc`'s configure demands of
  #    `-print-target-header-dir`. Each has been absent once, and each absence
  #    reads as a different component's bug.
  #
  # 5. ASK THE CONSUMER, NOT THE PRODUCER. Every step above can succeed while
  #    the result is unusable -- which is exactly what the two rejected
  #    approaches did. The driver's own diagnostic is the only check that can
  #    tell, so it is run: `-dumpspecs` reaches `set_up_specs`, which is what
  #    needs the config file, and it needs no assembler.
  ''
    mergeTree() {
      local src="$1" dest="$2" label="$3" e name
      for e in "$src"/*; do
        name=$(basename "$e")
        if [ -d "$e" ]; then
          mkdir -p "$dest/$name"
          mergeTree "$e" "$dest/$name" "$label/$name"
        elif [ -e "$dest/$name" ]; then
          echo "gcc-composed: both producers supply $label/$name;" >&2
          echo "  one of them would silently win. Resolve it rather than" >&2
          echo "  letting the merge order decide." >&2
          exit 1
        else
          ln -s "$e" "$dest/$name"
        fi
      done
    }

    mkdir -p "$out/bin" "$out/lib/gcc/${release_version}"

    for f in "${gcc-unwrapped}"/bin/*; do
      cp "$f" "$out/bin/$(basename "$f")"
    done
    chmod -R u+w "$out/bin"

    mkdir -p "$out/libexec/gcc/${release_version}"
    for src in "${gcc-unwrapped}/libexec/gcc/${release_version}" \
               "${lto-plugin}/libexec/gcc/${release_version}"; do
      test -d "$src" || continue
      for e in "$src"/*; do
        name=$(basename "$e")
        test -e "$out/libexec/gcc/${release_version}/$name" && {
          echo "gcc-composed: both producers supply libexec/gcc/*/$name;" >&2
          echo "  one of them would silently win." >&2
          exit 1; }
        ln -s "$e" "$out/libexec/gcc/${release_version}/$name"
      done
    done

    for f in cc1 lto-wrapper liblto_plugin.so; do
      test -e "$out/libexec/gcc/${release_version}/$f" || {
        echo "gcc-composed: no libexec/gcc/${release_version}/$f." >&2
        echo "  cc1 and lto-wrapper come from gcc; liblto_plugin.so comes" >&2
        echo "  from lto-plugin. An absent plugin is not an error anywhere:" >&2
        echo "  the driver emits a bare -plugin, which swallows the next" >&2
        echo "  argument on the link line." >&2
        exit 1; }
    done
    for d in "${gcc-unwrapped}"/lib/gcc/${release_version}/*; do
      ln -s "$d" "$out/lib/gcc/${release_version}/$(basename "$d")"
    done

    tdir="$out/lib/gcc/${release_version}/${target}"
    rm -f "$tdir"
    mkdir -p "$tdir"
    for src in "${gcc-unwrapped}/lib/gcc/${release_version}/${target}" \
               "${target-specs}/lib/gcc/${release_version}/${target}"; do
      test -d "$src" || continue
      mergeTree "$src" "$tdir" "lib/gcc/*/${target}"
    done

    for f in specs-config include/tm.h; do
      test -e "$tdir/$f" || {
        echo "gcc-composed: no $tdir/$f." >&2
        echo "  specs-config comes from target-specs; include/ comes from" >&2
        echo "  gcc's install-target-headers. Both land in this one directory." >&2
        exit 1; }
    done

    if ! "$out/bin/${target}-gcc" -dumpspecs > /dev/null 2>"$out/.probe"; then
      echo "gcc-composed: ${target}-gcc cannot read its own target config:" >&2
      cat "$out/.probe" >&2
      exit 1
    fi
    rm -f "$out/.probe"
    echo "gcc-composed: ${target}-gcc reads its config from $out"
  ''
