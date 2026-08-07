{
  lib,
  stdenv,
  stdenvNoCC,
  stdenvNoLibc,
  stdenvLibcMinimal,
  filterSource,
  filterPatches,
  patchesRoot,
  illumosSetupHook,
  make,
  install,
  version,
}:

lib.makeOverridable (
  attrs:
  let
    stdenv' =
      if attrs.noCC or false then
        stdenvNoCC
      else if attrs.noLibc or false then
        stdenvNoLibc
      else if attrs.libcMinimal or false then
        stdenvLibcMinimal
      else
        stdenv;

    pname = attrs.pname or (baseNameOf attrs.path);
    paths = [ attrs.path ] ++ attrs.extraPaths or [ ];
  in
  stdenv'.mkDerivation (
    {
      pname = "${pname}-illumos";
      inherit version;

      src = filterSource {
        inherit pname;
        inherit (attrs) path;
        extraPaths = attrs.extraPaths or [ ];
      };

      extraPaths = [ ];

      # Pick out just the hunks of the shared patch set that touch this
      # package's own subset of the tree, so that editing an unrelated hunk does
      # not rebuild this package. Set `autoPickPatches = false` to opt out.
      patches =
        lib.optionals (attrs.autoPickPatches or true) (filterPatches { } patchesRoot paths)
        ++ attrs.patches or [ ];

      nativeBuildInputs = [
        illumosSetupHook
        make
        install
      ]
      ++ (attrs.extraNativeBuildInputs or [ ]);

      COMPONENT_PATH = attrs.path or null;

      strictDeps = true;

      meta = with lib; {
        maintainers = with maintainers; [ ericson2314 ];
        platforms = platforms.illumos;
        license = licenses.cddl;
      };
    }
    // lib.optionalAttrs (attrs.headersOnly or false) {
      installPhase = "includesPhase";
      dontBuild = true;
    }
    // (builtins.removeAttrs attrs [
      "extraNativeBuildInputs"
      "autoPickPatches"
      "patches"
    ])
  )
)
