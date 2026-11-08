{
  config,
  pkgs,
  lib,
  options,
  ...
}:
let
  cfg = config.services.cloudflare-warp;
in
{
  options.services.cloudflare-warp = {
    enable = lib.mkEnableOption "the Cloudflare Zero Trust client daemon (`warp-svc`), controlled with `warp-cli`";

    package = lib.mkPackageOption pkgs "cloudflare-warp" {
      example = "pkgs.cloudflare-warp.override { headless = true; }";
      extraDescription = ''
        The package is unfree, so the `pkgs` the system is built with must allow it,
        otherwise evaluation fails with an error naming `cloudflare-warp`.

        `headless = true` builds it without the GUI.
      '';
    };

    udpPort = lib.mkOption {
      type = lib.types.port;
      default = 2408;
      description = ''
        The UDP port opened in the firewall when {option}`openFirewall` is set.

        This only controls what is opened, not what the daemon uses. Warp uses 2408 by
        default and falls back to other pre-configured ports where that one is taken, see
        the [firewall documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/deployment/firewall#warp-udp-ports).
      '';
    };

    openFirewall = lib.mkEnableOption "opening {option}`udpPort` in the firewall" // {
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # nothing autoloads tun from /dev/net/tun
    boot.kernelModules = [ "tun" ];

    providers.firewall.allowedUDPPorts = lib.mkIf cfg.openFirewall [ cfg.udpPort ];

    # warp-svc runs nft by this absolute path, not through $PATH
    finit.tmpfiles.rules = [ "L+ /usr/sbin/nft - - - - ${lib.getExe pkgs.nftables}" ];

    finit.services.cloudflare-warp = {
      description = "Cloudflare Zero Trust client daemon";

      conditions = [
        "service/syslogd/ready"
        "task/tmpfiles-setup/success"
      ]
      ++ lib.optional (options ? services.dbus && config.services.dbus.enable) "service/dbus/ready";

      # warp-svc has no flag for its working directory
      script = ''
        cd "$STATE_DIRECTORY"
        exec ${lib.getExe' cfg.package "warp-svc"}
      '';

      runtime-dir = "cloudflare-warp";
      logs-dir = "cloudflare-warp";
      state-dir = "cloudflare-warp";

      path = [ pkgs.lsof ];

      respawn = true;
    };
  };
}
