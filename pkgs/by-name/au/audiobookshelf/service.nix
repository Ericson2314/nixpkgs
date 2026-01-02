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
    description = "Audiobookshelf service configuration";
  };

  config = lib.optionalAttrs (options ? systemd) {
    systemd.service = {
      description = "Audiobookshelf is a self-hosted audiobook and podcast server";

      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = cfg.dataDir;
        WorkingDirectory = "/var/lib/${cfg.dataDir}";
        ExecStart = "${lib.getExe cfg.package} --host ${cfg.host} --port ${toString cfg.port}";
        Restart = "on-failure";
      };
    };
  };

  meta.maintainers = with lib.maintainers; [ wietsedv ];
}
