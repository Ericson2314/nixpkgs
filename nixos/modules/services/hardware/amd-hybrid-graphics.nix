{ config, pkgs, lib, ... }:

{

  ###### interface

  options = {

    hardware.amdHybridGraphics.disable = lib.mkOption {
      default = false;
      type = lib.types.bool;
      description = ''
        Completely disable the AMD graphics card and use the
        integrated graphics processor instead.
      '';
    };

  };


  ###### implementation

  config = lib.mkIf config.hardware.amdHybridGraphics.disable {
    systemd.services."amd-hybrid-graphics" = {
      path = [ pkgs.bash ];
      description = "Disable AMD Card";
      after = [ "sys-kernel-debug.mount" ];
      before = [ "systemd-vconsole-setup.service" "display-manager.service" ];
      requires = [ "sys-kernel-debug.mount" "vgaswitcheroo.path" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getShellPath pkgs.bash} -c 'echo -e \"IGD\\nOFF\" > /sys/kernel/debug/vgaswitcheroo/switch'";
        ExecStop = "${lib.getShellPath pkgs.bash} -c 'echo ON >/sys/kernel/debug/vgaswitcheroo/switch'";
      };
    };
    systemd.paths."vgaswitcheroo" = {
      pathConfig = {
        PathExists = "/sys/kernel/debug/vgaswitcheroo/switch";
        Unit = "amd-hybrid-graphics.service";
      };
      wantedBy = ["multi-user.target"];
    };
  };

}
