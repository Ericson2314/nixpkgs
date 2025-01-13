{
  lib,
  stdenv,
  stdenvNoCC,
  stdenvNoLibc,
  stdenvLibcMinimal,
  runCommand,
  rsync,
  source,
  illumosSetupHook,
  make,
  install,
#tsort,
#lorder,
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
  in
  stdenv'.mkDerivation (
    rec {
      pname = "${attrs.pname or (baseNameOf attrs.path)}-illumos";
      version = "0";
      src = runCommand "${pname}-filtered-src" { nativeBuildInputs = [ rsync ]; } ''
        for p in ${lib.concatStringsSep " " ([ attrs.path ] ++ attrs.extraPaths or [ ])}; do
          set -x
          path="$out/$p"
          mkdir -p "$(dirname "$path")"
          src_path="${source}/$p"
          if [[ -d "$src_path" ]]; then src_path+=/; fi
          rsync --chmod="+w" -r "$src_path" "$path"
          set +x
        done
      '';

      extraPaths = [ ];

      nativeBuildInputs = [
        illumosSetupHook
        make
        install
      ] ++ (attrs.extraNativeBuildInputs or [ ]);

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
    // (builtins.removeAttrs attrs [ "extraNativeBuildInputs" ])
  )
)
