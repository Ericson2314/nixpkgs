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
  ''
    rsync -a -r --files-from=${filterText} ${source}/ $out
  ''
