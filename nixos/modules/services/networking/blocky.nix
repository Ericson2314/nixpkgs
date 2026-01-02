{
  lib,
  pkgs,
  ...
}:

let
  makeModularServiceWrapper = import ../../../lib/make-modular-service-wrapper.nix { inherit lib; };
in
{
  imports = [
    (makeModularServiceWrapper {
      name = "blocky";
      package = pkgs.blocky;
      enableOption = lib.mkEnableOption "blocky, a fast and lightweight DNS proxy as ad-blocker for local network with many features";
      meta.maintainers = with lib.maintainers; [ paepcke ];
    })
  ];
}
