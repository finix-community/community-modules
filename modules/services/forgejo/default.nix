{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.forgejo;

  format = pkgs.formats.ini { };
  configFile = format.generate "app.ini" cfg.settings;
in
{
  options.services.forgejo = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable [forgejo](${pkgs.forgejo.meta.homepage}) as a system service.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.forgejo;
      defaultText = lib.literalExpression "pkgs.forgejo";
      description = ''
        The package to use for `forgejo`.
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/forgejo";
      description = ''
        The directory used to store all `forgejo` state.

        ::: {.note}
        If left as the default value this directory will automatically be created on
        system activation, otherwise you are responsible for ensuring the directory exists
        with appropriate ownership and permissions before the `forgejo` service starts.
        :::
      '';
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable debug logging.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "forgejo";
      description = ''
        User account under which `forgejo` runs.

        ::: {.note}
        If left as the default value this user will automatically be created
        on system activation, otherwise you are responsible for
        ensuring the user exists before the `forgejo` service starts.
        :::
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "forgejo";
      description = ''
        Group account under which `forgejo` runs.

        ::: {.note}
        If left as the default value this group will automatically be created
        on system activation, otherwise you are responsible for
        ensuring the group exists before the `forgejo` service starts.
        :::
      '';
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = format.type;

        options = {
          log = {
            ROOT_PATH = lib.mkOption {
              type = lib.types.str;
              default = "/var/log/forgejo";
            };

            LEVEL = lib.mkOption {
              type = lib.types.enum [
                "Trace"
                "Debug"
                "Info"
                "Warn"
                "Error"
                "Critical"
              ];
              default = "Info";
            };
          };

          oauth2 = {
            JWT_SECRET_URI = lib.mkOption {
              type = lib.types.str;
              default = "file:${cfg.stateDir}/custom/conf/oauth2_jwt_secret";
            };
          };

          security = {
            INTERNAL_TOKEN_URI = lib.mkOption {
              type = lib.types.str;
              default = "file:${cfg.stateDir}/custom/conf/internal_token";
            };

            SECRET_KEY_URI = lib.mkOption {
              type = lib.types.str;
              default = "file:${cfg.stateDir}/custom/conf/secret_key";
            };
          };

          server = {
            # DISABLE_SSH = lib.mkOption {
            #   type = lib.types.bool;
            #   default = false;
            # };

            HTTP_PORT = lib.mkOption {
              type = lib.types.port;
              default = 3000;
            };

            START_SSH_SERVER = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };

            SSH_PORT = lib.mkOption {
              type = lib.types.port;
              default = 22;
            };
          };

          session = {
            COOKIE_SECURE = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };
          };
        };
      };
      default = { };
      description = ''
        `forgejo` configuration. See [upstream documentation](https://forgejo.org/docs/latest/admin/config-cheat-sheet)
        for additional details.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.forgejo.settings = {
      DEFAULT = {
        RUN_MODE = if cfg.debug then "dev" else "prod";
        RUN_USER = cfg.user;
        WORK_PATH = cfg.stateDir;
      };

      log = {
        MODE = "file";
        LEVEL = lib.mkIf cfg.debug "Debug";
      };

      security = {
        INSTALL_LOCK = lib.mkDefault true;
      };
    };

    finit.services.forgejo = {
      inherit (cfg) user group;

      command = "${lib.getExe cfg.package} web --config ${configFile} --pid /run/forgejo/forgejo.pid";
      conditions = [ "service/syslogd/ready" ];
      notify = "systemd";
      nohup = true;
      path = [ config.programs.coreutils.package ];
      environment = {
        USER = cfg.user;
        HOME = cfg.stateDir;
      };
      caps = [ "^cap_net_bind_service" ];
      log = true;

      pre = pkgs.writeShellScript "generate-secrets.sh" ''
        if [ ! -s '${lib.removePrefix "file:" cfg.settings.security.INTERNAL_TOKEN_URI}' ]; then
          ${lib.getExe cfg.package} generate secret INTERNAL_TOKEN > '${lib.removePrefix "file:" cfg.settings.security.INTERNAL_TOKEN_URI}'
        fi

        if [ ! -s '${lib.removePrefix "file:" cfg.settings.oauth2.JWT_SECRET_URI}' ]; then
          ${lib.getExe cfg.package} generate secret JWT_SECRET > '${lib.removePrefix "file:" cfg.settings.oauth2.JWT_SECRET_URI}'
        fi

        if [ ! -s '${lib.removePrefix "file:" cfg.settings.security.SECRET_KEY_URI}' ]; then
          ${lib.getExe cfg.package} generate secret SECRET_KEY > '${lib.removePrefix "file:" cfg.settings.security.SECRET_KEY_URI}'
        fi
      '';
    };

    finit.tmpfiles.rules = [
      "d /run/forgejo 0755 ${cfg.user} ${cfg.group}"
    ]
    ++ lib.optionals (cfg.stateDir == "/var/lib/forgejo") [
      "d /var/lib/forgejo 0750 ${cfg.user} ${cfg.group}"
      "d /var/lib/forgejo/custom - ${cfg.user} ${cfg.group}"
      "d /var/lib/forgejo/custom/conf - ${cfg.user} ${cfg.group}"
    ]
    ++ lib.optionals (cfg.settings.log.ROOT_PATH == "/var/log/forgejo") [
      "d /var/log/forgejo 0750 ${cfg.user} ${cfg.group}"
    ];

    users.users = lib.optionalAttrs (cfg.user == "forgejo") {
      forgejo = {
        inherit (cfg) group;

        home = cfg.stateDir;
        shell = pkgs.bashInteractive; # TODO: useDefaultShell = true;
        isSystemUser = true;
      };
    };

    users.groups = lib.optionalAttrs (cfg.group == "forgejo") {
      forgejo = { };
    };
  };
}
