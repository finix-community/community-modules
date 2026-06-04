{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.tailscale;
  tun = cfg.interfaceName != "userspace-networking";

  routingSysctls =
    lib.optionalAttrs
      (builtins.elem cfg.routingSysctls [
        "server"
        "both"
      ])
      {
        "net.ipv4.conf.all.forwarding" = lib.mkDefault true;
        "net.ipv6.conf.all.forwarding" = lib.mkDefault true;
      }
    //
      lib.optionalAttrs
        (builtins.elem cfg.routingSysctls [
          "client"
          "both"
        ])
        {
          "net.ipv4.conf.all.rp_filter" = lib.mkDefault 2;
          "net.ipv4.conf.default.rp_filter" = lib.mkDefault 2;
        };

  daemonFlags = (
    [
      "--state=${cfg.stateDir}/tailscaled.state"
      "--port=${toString cfg.port}"
      "--socket=/run/tailscale/tailscaled.sock"
      "--tun=${cfg.interfaceName}"
    ]
    ++ cfg.extraDaemonFlags
  );

  paramToString = v: if builtins.isBool v then lib.boolToString v else toString v;
  authKeyParams = lib.pipe cfg.authKeyParameters [
    (lib.filterAttrs (_: v: v != null))
    (lib.mapAttrsToList (k: v: "${k}=${paramToString v}"))
    (builtins.concatStringsSep "&")
    (params: if params != "" then "?${params}" else "")
  ];
in
{
  meta.maintainers = with lib.maintainers; [ willowispll ];

  options.services.tailscale = {
    enable = lib.mkEnableOption "tailscale";
    package = lib.mkPackageOption pkgs "tailscale" { };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/tailscale";
      description = ''
        The directory used to store all `tailscale` data. If changed, you are responsible
        for ensuring the directory exists with appropriate ownership and permissions before
        the `tailscaled` service starts.
      '';
    };

    interfaceName = lib.mkOption {
      type = lib.types.str;
      default = "tailscale0";
      description = ''
        The interface name for tunnel traffic. Use `"userspace-networking"` (beta) to not use TUN.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 41641;
      description = ''
        The port to listen on for tunnel traffic (0 = autoselect).
      '';
    };

    routingSysctls = lib.mkOption {
      type = lib.types.enum [
        "none"
        "client"
        "server"
        "both"
      ];
      default = "none";
      description = ''
        Enables settings required for subnet routers and exit nodes.

        client:
          enables loose reverse-path filtering
        server:
          enables IPv4/IPv6 forwarding
        both:
          enables both
      '';
    };

    authKeyFile = lib.mkOption {
      type = with lib.types; nullOr path;
      default = null;
      example = "/run/secrets/tailscale_key";
      description = ''
        A file containing the auth key.
        If provided, `tailscale up` will be executed automatically.
      '';
    };

    authKeyParameters = lib.mkOption {
      type = lib.types.submodule {
        options = {
          ephemeral = lib.mkOption {
            type = with lib.types; nullOr bool;
            default = null;
          };
          preauthorized = lib.mkOption {
            type = with lib.types; nullOr bool;
            default = null;
          };
          baseURL = lib.mkOption {
            type = with lib.types; nullOr str;
            default = null;
          };
        };
      };
      default = { };
      description = ''
        Extra parameters to pass after the auth key.
        See <https://tailscale.com/kb/1215/oauth-clients#registering-new-nodes-using-oauth-credentials>
      '';
    };

    extraUpFlags = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      example = [
        "--ssh"
        "--advertise-exit-node"
      ];
      description = ''
        Extra flags to pass to `tailscale up`.
      '';
    };

    extraDaemonFlags = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = ''
        Extra flags to pass to `tailscaled`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    boot = {
      kernelModules = lib.optionals tun [ "tun" ];
      kernel.sysctl = routingSysctls;
    };

    services.dhcpcd.settings.denyinterfaces = lib.optionals tun [ cfg.interfaceName ];

    finit.tmpfiles.rules = [
      "d /run/tailscale 0755 root root"
      "d ${cfg.stateDir} 0700 root root"
    ];

    finit.services.tailscaled = {
      description = "tailscaled";
      conditions = [
        "service/syslogd/ready"
        "net/route/default"
      ];
      command = "${cfg.package}/bin/tailscaled " + lib.escapeShellArgs daemonFlags;
      post = "";
      path = [
        (dirOf config.security.wrapperDir)
        pkgs.procps
        pkgs.getent
        pkgs.kmod
      ];
      respawn = true;
      log = true;
    };

    finit.tasks.tailscale-up = lib.mkIf (cfg.authKeyFile != null || cfg.extraUpFlags != [ ]) {
      description = "tailscale up";

      conditions = [
        "service/tailscaled/running"
      ];

      command = ''
        sleep 2

        AUTH=""
        ${lib.optionalString (cfg.authKeyFile != null) ''
          AUTH="--auth-key $(cat ${cfg.authKeyFile})${authKeyParams}"
        ''}
        exec ${cfg.package}/bin/tailscale up \
          $AUTH \
          ${lib.escapeShellArgs cfg.extraUpFlags}
      '';
      log = true;
    };
  };
}
