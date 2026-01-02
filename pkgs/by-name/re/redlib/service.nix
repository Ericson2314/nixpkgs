{
  config,
  options,
  lib,
  ...
}:

let
  inherit (lib)
    isBool
    mapAttrs
    ;

  cfg = config.thisService;

  boolToString' = b: if b then "on" else "off";
in
{
  _class = "service";

  options.thisService = lib.mkOption {
    type = lib.types.submodule {
      imports = [ ./service-options.nix ];
    };
    default = { };
    description = "Redlib service configuration";
  };

  config = {
    process.argv = [
      (lib.getExe cfg.package)
      "--port"
      (toString cfg.port)
      "--address"
      cfg.address
    ];
  }
  // lib.optionalAttrs (options ? systemd) {
    #systemd.packages = [ cfg.package ];
    systemd.service = {
      wantedBy = [ "default.target" ];
      environment = mapAttrs (_: v: if isBool v then boolToString' v else toString v) cfg.settings;
      serviceConfig = {
        # Reset the ExecStart from the portable service interface
        ExecStart = lib.mkBefore [ "" ];
        # Hardening
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateIPC = true;
        PrivateTmp = true;
        ProcSubset = "pid";
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "full";
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "~@mount"
          "~@swap"
          "~@resources"
          "~@reboot"
          "~@raw-io"
          "~@obsolete"
          "~@module"
          "~@debug"
          "~@cpu-emulation"
          "~@clock"
          "~@privileged"
        ];
        UMask = "0027";
      }
      // (
        if (cfg.port < 1024) then
          {
            AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
            CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
          }
        else
          {
            # A private user cannot have process capabilities on the host's user
            # namespace and thus CAP_NET_BIND_SERVICE has no effect.
            PrivateUsers = true;
            CapabilityBoundingSet = false;
          }
      );
    };
  };

  meta = {
    maintainers = with lib.maintainers; [ Guanran928 ];
  };
}
