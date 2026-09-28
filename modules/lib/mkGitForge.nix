{ name, packageAttr ? name }:
{ config, pkgs, lib, ... }:
let
  cfg = config.services.${name};
  package = pkgs.${packageAttr};

  format = pkgs.formats.ini { };
  configFile = format.generate "app.ini" cfg.settings;
in
{
  options.services.${name} = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable [${name}](${package.meta.homepage}) as a system service.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      defaultText = lib.literalExpression "pkgs.${packageAttr}";
      description = ''
        The package to use for `${name}`.
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/${name}";
      description = ''
        The directory used to store all `${name}` state.

        ::: {.note}
        If left as the default value this directory will automatically be created on
        system activation, otherwise you are responsible for ensuring the directory exists
        with appropriate ownership and permissions before the `${name}` service starts.
        :::
      '';
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enable debug logging.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = name;
      description = ''
        User account under which `${name}` runs.

        ::: {.note}
        If left as the default value this user will automatically be created
        on system activation, otherwise you are responsible for
        ensuring the user exists before the `${name}` service starts.
        :::
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = name;
      description = ''
        Group account under which `${name}` runs.

        ::: {.note}
        If left as the default value this group will automatically be created
        on system activation, otherwise you are responsible for
        ensuring the group exists before the `${name}` service starts.
        :::
      '';
    };

    database = {
      type = lib.mkOption {
        type = lib.types.enum [ "sqlite3" "postgres" "mysql" ];
        default = "sqlite3";
        description = "Database engine used by `${name}`.";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Database host (ignored for sqlite3).";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = if cfg.database.type == "mysql" then 3306 else 5432;
        defaultText = lib.literalExpression ''if cfg.database.type == "mysql" then 3306 else 5432'';
        description = "Database port (ignored for sqlite3).";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Database name (ignored for sqlite3).";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Database user (ignored for sqlite3).";
      };

      path = lib.mkOption {
        type = lib.types.str;
        default = "${cfg.stateDir}/data/${name}.db";
        description = "Path to the sqlite3 database file (only used when `type = \"sqlite3\"`).";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to a file containing the database password.

          ::: {.note}
          Prefer this over embedding a password in `settings.database` directly,
          since that would be world-readable in the Nix store.
          :::
        '';
      };

      createDatabase = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to automatically provision the local database and user
          via `services.postgresql` / `services.mysql`.

          ::: {.warning}
          Not yet supported on finix: those service modules don't exist here
          yet, so setting `type` to `postgres` or `mysql` with this left at
          its default of `true` will fail an assertion at eval time. Set this
          to `false` and manage the database yourself in the meantime.
          :::

          Has no effect when `type = "sqlite3"`.
        '';
      };
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = format.type;

        options = {
          log = {
            ROOT_PATH = lib.mkOption {
              type = lib.types.str;
              default = "/var/log/${name}";
            };

            LEVEL = lib.mkOption {
              type = lib.types.enum [ "Trace" "Debug" "Info" "Warn" "Error" "Critical" ];
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
        `${name}` configuration. See upstream config-cheat-sheet docs for additional details.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.database.type == "sqlite3" || !cfg.database.createDatabase;
        message = ''
          services.${name}.database.type = "${cfg.database.type}" with createDatabase = true is not
          supported yet: finix does not currently provide `services.postgresql` / `services.mysql`
          modules, so this module cannot auto-provision the database for you.

          Either set services.${name}.database.type = "sqlite3" (the default), or set
          services.${name}.database.createDatabase = false and point database.host/port/user
          at a database you provision and manage yourself.
        '';
      }
    ];

    services.${name}.settings = {
      DEFAULT = {
        RUN_MODE = if cfg.debug then "dev" else "prod";
        RUN_USER = cfg.user;
        WORK_PATH = cfg.stateDir;
      };

      log = {
        MODE = "file";
        LEVEL = lib.mkIf cfg.debug "Debug";
      };

      security.INSTALL_LOCK = lib.mkDefault true;

      database =
        {
          DB_TYPE = cfg.database.type;
          NAME = cfg.database.name;
          USER = cfg.database.user;
          PATH = cfg.database.path;
        }
        // lib.optionalAttrs (cfg.database.type != "sqlite3") {
          HOST = "${cfg.database.host}:${toString cfg.database.port}";
        }
        // lib.optionalAttrs (cfg.database.passwordFile != null) {
          # gitea/forgejo support the `KEY__FILE` convention: read the value
          # from a file at startup instead of embedding it in app.ini.
          PASSWD__FILE = cfg.database.passwordFile;
        };
    };

    finit.services.${name} = {
      inherit (cfg) user group;

      command = "${lib.getExe cfg.package} web --config ${configFile} --pid /run/${name}/${name}.pid";
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

      pre = pkgs.writeShellScript "generate-${name}-secrets.sh" (
        lib.concatMapStringsSep "\n"
          (secret: ''
            if [ ! -s '${lib.removePrefix "file:" cfg.settings.${secret.section}.${secret.key}}' ]; then
              ${lib.getExe cfg.package} generate secret ${secret.name} > '${lib.removePrefix "file:" cfg.settings.${secret.section}.${secret.key}}'
            fi
          '')
          [
            { section = "security"; key = "INTERNAL_TOKEN_URI"; name = "INTERNAL_TOKEN"; }
            { section = "oauth2"; key = "JWT_SECRET_URI"; name = "JWT_SECRET"; }
            { section = "security"; key = "SECRET_KEY_URI"; name = "SECRET_KEY"; }
          ]
      );
    };

    finit.tmpfiles.rules = [
      "d /run/${name} 0755 ${cfg.user} ${cfg.group}"
    ]
    ++ lib.optionals (cfg.stateDir == "/var/lib/${name}") [
      "d /var/lib/${name} 0750 ${cfg.user} ${cfg.group}"
      "d /var/lib/${name}/custom - ${cfg.user} ${cfg.group}"
      "d /var/lib/${name}/custom/conf - ${cfg.user} ${cfg.group}"
      "d /var/lib/${name}/data - ${cfg.user} ${cfg.group}"
    ]
    ++ lib.optionals (cfg.settings.log.ROOT_PATH == "/var/log/${name}") [
      "d /var/log/${name} 0750 ${cfg.user} ${cfg.group}"
    ];

    users.users = lib.optionalAttrs (cfg.user == name) {
      ${name} = {
        inherit (cfg) group;
        home = cfg.stateDir;
        shell = pkgs.bashInteractive;
        isSystemUser = true;
      };
    };

    users.groups = lib.optionalAttrs (cfg.group == name) {
      ${name} = { };
    };
  };
}
