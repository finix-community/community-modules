{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.amnezia-vpn;
in
{
  options.programs.amnezia-vpn = {
    enable = lib.mkEnableOption "The AmneziaVPN client";
    package = lib.mkPackageOption pkgs "amnezia-vpn" { };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    services.dbus.enable = true;
    services.dbus.packages = [ cfg.package ];

    programs.resolvconf.enable = true;

    finit.services.amnezia-vpn = {
      description = "AmneziaVPN daemon";
      runlevels = "2345";
      command = "${cfg.package}/bin/AmneziaVPN-service";
      path = with pkgs; [
        procps
        iproute2
        sudo
      ];
    };
  };

  meta.maintainers = with lib.maintainers; [ willowispll ];
}
