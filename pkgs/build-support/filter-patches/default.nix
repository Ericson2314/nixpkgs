{
  lib,
  writeText,
}:

# Takes a list of patches and a list of paths, and returns a list of
# derivations -- one per patched file -- containing just the hunks of those
# patches that touch the given paths.
#
# This exists so that a package built from a subset of a large source tree only
# depends on the parts of a patch that actually affect its subset. Without it,
# a single shared patch file makes every package that applies it rebuild
# whenever any hunk anywhere in that file changes.
#
# Note that the split output deliberately drops each patch's preamble --
# `diff --git` lines, `index` lines, and anything before the first `--- `
# header. Commit metadata therefore does not contribute to the hash, so
# regenerating patches from rebased commits does not cause rebuilds.
#
# The "list of patches" argument can be a directory containing patch files, a
# path, a derivation, or a (recursively) nested list of those.
#
# `fragmentName` names the generated per-file derivations. It only exists so
# that existing callers can keep their current store paths, and hence avoid a
# mass rebuild, when they move to this shared implementation.

{ fragmentName ? "filtered-patch" }:
patches: paths:
let
  isDir =
    file:
    let
      base = baseNameOf file;
      type = (builtins.readDir (dirOf file)).${base} or null;
    in
    file == /. || type == "directory";

  consolidatePatches =
    patches:
    if (lib.isDerivation patches) then
      [ patches ]
    else if (builtins.isPath patches) then
      (if (isDir patches) then (lib.filesystem.listFilesRecursive patches) else [ patches ])
    else if (builtins.isList patches) then
      (lib.flatten (builtins.map consolidatePatches patches))
    else
      throw "Bad patches - must be path or derivation or list thereof";

  consolidated = consolidatePatches patches;

  splitPatch =
    patchFile:
    let
      allLines' = lib.strings.splitString "\n" (builtins.readFile patchFile);
      allLines = builtins.filter (
        line: !((lib.strings.hasPrefix "diff --git" line) || (lib.strings.hasPrefix "index " line))
      ) allLines';
      foldFunc =
        a: b:
        if ((lib.strings.hasPrefix "--- " b) || (lib.strings.hasPrefix "diff --git " b)) then
          (a ++ [ [ b ] ])
        else
          ((lib.lists.init a) ++ (lib.lists.singleton ((lib.lists.last a) ++ [ b ])));
      partitionedPatches' = lib.lists.foldl foldFunc [ [ ] ] allLines;
      partitionedPatches =
        if (builtins.length partitionedPatches' > 1) then
          (lib.lists.drop 1 partitionedPatches')
        else
          (throw "${patchFile} does not seem to be a unified patch (diff -u). this is required.");
      filterFunc =
        patchLines:
        let
          prefixedPath = builtins.elemAt (builtins.split " |\t" (builtins.elemAt patchLines 1)) 2;
          unfixedPath = lib.path.subpath.join (lib.lists.drop 1 (lib.path.subpath.components prefixedPath));
        in
        lib.lists.any (
          included: lib.path.hasPrefix (/. + ("/" + included)) (/. + ("/" + unfixedPath))
        ) paths;
      filteredLines = builtins.filter filterFunc partitionedPatches;
      derive = patchLines: writeText fragmentName (lib.concatLines patchLines);
    in
    builtins.map derive filteredLines;
in
lib.lists.concatMap splitPatch consolidated
