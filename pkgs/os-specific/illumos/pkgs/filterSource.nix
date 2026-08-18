{
  lib,
  pkgsBuildBuild,
  runCommand,
  writeText,
  source,
}:

{
  pname,
  path,
  extraPaths ? [ ],
}:

let
  sortedPaths = lib.naturalSort ([ path ] ++ extraPaths);
  filterText = writeText "${pname}-src-include" (
    lib.concatMapStringsSep "\n" (path: "/${path}") sortedPaths
  );
in
runCommand "${pname}-filtered-src"
  {
    nativeBuildInputs = [
      # Trimmed down to keep the bootstrap closure small; none of these features
      # matter for copying a source subtree.
      (
        (pkgsBuildBuild.rsync.override {
          enableZstd = false;
          enableXXHash = false;
          enableOpenSSL = false;
          enableLZ4 = false;
        }).overrideAttrs
        {
          doCheck = false;
        }
      )
    ];
  }
  # `--ignore-missing-args`: a path may legitimately be absent from the pinned
  # upstream tarball and be *created by a patch*. `usr/src/tools/libcompat` is
  # the first such case -- it exists only by virtue of the libcompat merge
  # patch, which is applied after this filtering step, yet packages must be able
  # to name it in `extraPaths` so that it survives into their source tree.
  # Without this flag rsync exits 23 on the missing path and the whole
  # derivation fails, taking `ld` -- and therefore libc and every kernel
  # module -- with it.
  #
  # The cost is real and worth stating: a typo in `extraPaths` now silently
  # copies nothing instead of failing loudly. If a package mysteriously cannot
  # see a file it names, suspect the spelling here first.
  ''
    rsync -a -r --ignore-missing-args --files-from=${filterText} ${source}/ $out
  ''
