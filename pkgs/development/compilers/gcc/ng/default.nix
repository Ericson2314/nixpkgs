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
  fetchFromGitHub,
  ...
}@packageSetArgs:
let
  # illumos cannot use upstream GCC: it needs the ABI and runtime-linker support
  # the platform depends on -- `-msave-args` (DTrace and `mdb` read stack
  # arguments), `-fstrict-calling-conventions`, disabled function cloning,
  # `__illumos__`, illumos libc SSP, and `-G` implying `-shared` in the specs.
  # The fork is rebased onto the 15.2.0 release, so it replaces the upstream
  # 15.x tarball entirely rather than sitting alongside it.
  illumosVersions = {
    "15.2.0" = {
      # Unused (`monorepoSrc` wins), but `common-let.nix` wants one of
      # `officialRelease`/`gitRelease` to be an attrset.
      officialRelease = { };
      monorepoSrc = fetchFromGitHub {
        owner = "Ericson2314";
        repo = "gcc";
        rev = "84e2e22d108fd9cf5de1d062c137a5f68c27800c";
        hash = "sha256-8TZRxdc7I+lkeIAjovZXDi3F1RvWOdcvGnWBQct2/bI=";
      };
      # A git checkout lacks the generated sources (gengtype-lex.cc and
      # friends) that a release tarball ships pre-built.
      fromVCS = true;
    };
  };

  versions =
    (
      if stdenv.targetPlatform.isIllumos then
        illumosVersions
      else
        {
          "15.3.0".officialRelease.sha256 = "sha256-+lnBvu+JlfJ8TXHB3yJ1hxiTFdPm+v8btDBuYbDFMOs=";
        }
    )
    // gccVersions;

  mkPackage =
    {
      name ? null,
      officialRelease ? null,
      gitRelease ? null,
      monorepoSrc ? null,
      version ? null,
      fromVCS ? false,
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
              fromVCS
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
