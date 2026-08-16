{
  lib,
  callPackage,
  stdenv,
  stdenvAdapters,
  gccVersions ? { },
  patchesFn ? lib.id,
  buildPackages,
  targetPackages,
  binutilsNoLibc,
  binutils,
  generateSplicesForMkScope,
  fetchgit,
  ...
}@packageSetArgs:
let
  # THE MULTI-TARGET BRANCH, NOT A RELEASE TARBALL, AND THERE IS NO SECOND ARM.
  #
  # This set builds one compiler serving many back ends. Nothing released can
  # do that: `--enable-targets` (top level) and `--enable-backends` (`gcc/`)
  # exist only on `multi-target-0`, and autoconf accepts an unrecognised
  # `--enable-*` with a warning rather than an error. So a tarball build took
  # the flag, ignored it, and produced an ordinary single-target compiler --
  # and every `mt-compare.nix` run against it was two identical native
  # compilers agreeing, which is not evidence of anything.
  #
  # WHY NOT A VERSION-CONDITIONAL. `gcc/configure` on the branch *requires*
  # `--enable-backends` (`gcc/configure.ac:1653`,
  # `AC_MSG_ERROR([--enable-backends=LIST is required])`), so one expression
  # cannot serve both trees without branching on the version. That branch would
  # keep alive precisely the arm this set exists to disprove: a single-target
  # GCC that passes every check here because the checks cannot see the
  # difference. A set whose README says "the compiler stops depending on the
  # target" must not ship a compiler that does. So: wholesale.
  #
  # Fetched from the local checkout because the branch is not published. The
  # `rev` is the authority; a working tree would put uncommitted state into a
  # store path.
  branchRev = "491713a900a069a5d9b590e1cf5a7f38a7dd5dfe";
  versions = {
    # `17.0.0` is `gcc/BASE-VER` in that tree: the branch is cut from trunk, not
    # from the 15 series, and calling it 15 here would be a second authority
    # for a version the source already states.
    "17.0.0" = {
      name = "17";
      gitRelease = {
        rev = branchRev;
        version = "17.0.0";
        rev-version = "17.0.0-multi-target-${builtins.substring 0 7 branchRev}";
      };
      # Named here rather than left to `common-let.nix`, whose `fetchgit` arm
      # hardcodes `gcc.gnu.org`. No `sha256` is given in `gitRelease` above for
      # the same reason: an unused hash next to the one that is used is a
      # second authority for one fact.
      monorepoSrc = fetchgit {
        url = "file:///home/jcericson/src/gnu/gcc/multi-target";
        rev = branchRev;
        hash = "sha256-qTCN2ifm9mH69sdgMSz0LVFdX6Bv/z+U8uRhz1xoz5g=";
      };
    };
  }
  // gccVersions;

  mkPackage =
    {
      name ? null,
      officialRelease ? null,
      gitRelease ? null,
      monorepoSrc ? null,
      version ? null,
    }@args:
    let
      inherit
        (import ./common/common-let.nix {
          inherit
            lib
            gitRelease
            officialRelease
            version
            ;
        })
        releaseInfo
        ;
      inherit (releaseInfo) release_version;
      attrName =
        args.name or (if (gitRelease != null) then "git" else lib.versions.major release_version);
    in
    lib.nameValuePair attrName (
      lib.recurseIntoAttrs (
        callPackage ./common (
          {
            inherit (stdenvAdapters) overrideCC;
            inherit
              officialRelease
              gitRelease
              monorepoSrc
              version
              patchesFn
              ;

            buildGccPackages = buildPackages."gccNGPackages_${attrName}";
            targetGccPackages = targetPackages."gccNGPackages_${attrName}" or gccPackages."${attrName}";
            otherSplices = generateSplicesForMkScope "gccNGPackages_${attrName}";
          }
          // packageSetArgs # Allow overrides.
        )
      )
    );

  gccPackages = lib.mapAttrs' (version: args: mkPackage (args // { inherit version; })) versions;
in
gccPackages // { inherit mkPackage; }
