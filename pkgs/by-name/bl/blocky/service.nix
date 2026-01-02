{
  config,
  options,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.thisService;

  format = pkgs.formats.yaml { };
  configFile = format.generate "config.yaml" cfg.settings;
in
{
  _class = "service";

  options.thisService = lib.mkOption {
    type = lib.types.submodule {
      imports = [ ./service-options.nix ];
    };
    default = { };
    description = "Blocky service configuration";
  };

  config = lib.optionalAttrs (options ? systemd) {
    systemd.service = {
      description = "A DNS proxy and ad-blocker for the local network";
      wants = [
        "network-online.target"
        "nss-lookup.target"
      ];
      before = [
        "nss-lookup.target"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} --config ${configFile}";
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        DynamicUser = true;
        LockPersonality = true;
        LogsDirectory = "blocky";
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        NonBlocking = true;
        PrivateDevices = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        Restart = "on-failure";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RuntimeDirectory = "blocky";
        StateDirectory = "blocky";
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "@chown"
          "~@aio"
          "~@keyring"
          "~@memlock"
          "~@setuid"
          "~@timer"
        ];
      };
    };
  };

  meta.maintainers = with lib.maintainers; [ paepcke ];
}
