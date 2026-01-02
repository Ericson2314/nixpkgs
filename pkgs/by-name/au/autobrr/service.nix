{
  config,
  options,
  lib,
  ...
}:

let
  cfg = config.thisService;
in
{
  _class = "service";

  options.thisService = lib.mkOption {
    type = lib.types.submodule {
      imports = [ ./service-options.nix ];
    };
    default = { };
    description = "Autobrr service configuration";
  };

  config = lib.optionalAttrs (options ? systemd) (
    let
      pkgs = config._module.args.pkgs;
      configFormat = pkgs.formats.toml { };
      configTemplate = configFormat.generate "autobrr.toml" cfg.settings;
    in
    {
      assertions = [
        {
          assertion = !(cfg.settings ? sessionSecret);
          message = ''
            Session secrets should not be passed via settings, as
            these are stored in the world-readable nix store.

            Use the secretFile option instead.'';
        }
      ];

      systemd.service = {
        description = "Autobrr";
        after = [
          "syslog.target"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          DynamicUser = true;
          LoadCredential = "sessionSecret:${cfg.secretFile}";
          StateDirectory = "autobrr";
          ExecStartPre = "${lib.getExe pkgs.bash} -c '${lib.getExe pkgs.dasel} put -f \"${configTemplate}\" -v \"$(systemd-creds cat sessionSecret)\" -o %S/autobrr/config.toml \"sessionSecret\"'";
          ExecStart = "${lib.getExe cfg.package} --config %S/autobrr";
          Restart = "on-failure";
        };
      };
    }
  );

  meta.maintainers = with lib.maintainers; [ av-gal ];
}
