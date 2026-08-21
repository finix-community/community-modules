{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.cups;

  format = pkgs.formats.keyValue {
    listsAsDuplicateKeys = true;
    mkKeyValue = lib.generators.mkKeyValueDefault { } " ";
  };

  # chgrp USB devices that have a printer interface (class 07)
  chgrpPrinter = pkgs.writeShellScript "mdevd-chgrp-printer" ''
    for iface in /sys/$DEVPATH/*/bInterfaceClass; do
      [ -f "$iface" ] && read cls < "$iface" && [ "$cls" = "07" ] && chgrp ${cfg.group} /dev/$MDEV && exit 0
    done
  '';

  # Merge CUPS outputs + filters + drivers into one ServerBin tree
  bindir = pkgs.buildEnv {
    name = "cups-progs";
    paths = [
      cfg.package.out
      pkgs.libcupsfilters
      pkgs.cups-filters
      pkgs.ghostscript
    ]
    ++ cfg.drivers;
    pathsToLink = [
      "/lib"
      "/share/cups"
      "/bin"
    ];
    ignoreCollisions = true;
  };

  # Default cupsd.conf — only placed if /etc/cups/cupsd.conf doesn't exist
  defaultCupsdConf = pkgs.writeText "cupsd.conf" ''
    LogLevel info
    Listen localhost:631
    Listen /run/cups/cups.sock
    WebInterface Yes
    DefaultAuthType Basic

    <Location />
      Order allow,deny
      Allow localhost
    </Location>
    <Location /admin>
      Order allow,deny
      Allow localhost
    </Location>
    <Location /admin/conf>
      AuthType Basic
      Require user @SYSTEM
      Order allow,deny
      Allow localhost
    </Location>
  '';
in
{
  options.services.cups = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.cups;
    };
    drivers = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
    };
    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = format.type;
        options = {
          SystemGroup = lib.mkOption {
            type = with lib.types; listOf str;
            default = [
              "root"
              "wheel"
              "lpadmin"
            ];
            apply = lib.concatStringsSep " ";
            description = "Specifies the group(s) to use for @SYSTEM group authentication.";
          };

          ServerBin = lib.mkOption {
            type = lib.types.str;
            default = "${bindir}/lib/cups";
            description = "Specifies the directory containing the backends, CGI programs, filters, helper programs, notifiers, and port monitors.";
          };

          DataDir = lib.mkOption {
            type = lib.types.str;
            default = "${bindir}/share/cups";
            description = "Specifies the directory where data files can be found.";
          };

          DocumentRoot = lib.mkOption {
            type = lib.types.str;
            default = "${cfg.package.out}/share/doc/cups";
            description = "Specifies the root directory for the CUPS web interface content.";
          };

          SetEnv = lib.mkOption {
            type = with lib.types; attrsOf str;
            default = { };
            apply = lib.mapAttrsToList (k: v: "${k} ${v}");
            description = "Set the specified environment variable to be passed to child processes. Note: the standard CUPS filter and backend environment variables cannot be overridden using this directive.";
          };

          AccessLog = lib.mkOption {
            type = lib.types.str;
            default = "stderr";
            description = ''Defines the access log filename. Specifying a blank filename disables access log generation. The value "stderr" causes log entries to be sent to the standard error file when the scheduler is running in the foreground, or to the system log daemon when run in the background. The value "syslog" causes log entries to be sent to the system log daemon.'';
          };

          ErrorLog = lib.mkOption {
            type = lib.types.str;
            default = "stderr";
            description = ''Defines the error log filename. Specifying a blank filename disables error log generation. The value "stderr" causes log entries to be sent to the standard error file when the scheduler is running in the foreground, or to the system log daemon when run in the background. The value "syslog" causes log entries to be sent to the system log daemon.'';
          };

          PageLog = lib.mkOption {
            type = lib.types.str;
            default = "stderr";
            description = ''Defines the page log filename. The value "stderr" causes log entries to be sent to the standard error file when the scheduler is running in the foreground, or to the system log daemon when run in the background. The value "syslog" causes log entries to be sent to the system log daemon. Specifying a blank filename disables page log generation.'';
          };
        };
      };
      default = { };
      description = "Settings for cups-files.conf. See cups-files.conf(5).";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "cups";
      description = ''
        User account under which `cups` executes external programs.

        ::: {.note}
        If left as the default value this user will automatically be created
        on system activation, otherwise you are responsible for
        ensuring the user exists before the `cups` service starts.
        :::
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "lp";
      description = ''
        Group account under which `cups` executes external programs.

        ::: {.note}
        If left as the default value this group will automatically be created
        on system activation, otherwise you are responsible for
        ensuring the group exists before the `cups` service starts.
        :::
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.cups.settings = {
      SetEnv.PATH = "${bindir}/lib/cups/filter:${bindir}/bin";

      User = lib.mkForce cfg.user;
      Group = lib.mkForce cfg.group;
    };

    # boot.blacklistedKernelModules = [ "usblp" ];
    environment.etc."modprobe.d/usblp.conf".text = ''
      blacklist usblp
    '';

    services.mdevd.hotplugRules = lib.mkIf (config.services.mdevd.enable) (
      lib.mkBefore ''
        -SUBSYSTEM=usb;DEVTYPE=usb_device;.* root:root 0660 @${chgrpPrinter}
      ''
    );

    services.udev.packages = lib.mkIf (config.services.udev.enable) cfg.drivers;

    environment.systemPackages = [ cfg.package.out ];

    finit.services.cups = {
      description = "CUPS printing daemon";
      conditions = "service/syslogd/ready";
      command = "${cfg.package.out}/sbin/cupsd -f -c /etc/cups/cupsd.conf -s ${format.generate "cups-files.conf" cfg.settings}";
      log = true;
    };

    finit.tmpfiles.rules = [
      "d /etc/cups 0755 root ${cfg.group}"
      "d /run/cups 0755 root ${cfg.group}"
      "d /var/cache/cups 0700 root ${cfg.group}"
      "d /var/lib/cups 0755 root ${cfg.group}"
      "d /var/spool/cups 0700 root ${cfg.group}"
      "d /var/spool/cups/tmp 0700 root ${cfg.group}"

      # place default cupsd.conf only if one doesn't already exist
      "C /etc/cups/cupsd.conf - - - - ${defaultCupsdConf}"
      "f /etc/cups/snmp.conf - - - - Address @LOCAL"
      "f /etc/cups/client.conf"
    ];

    users.users = lib.optionalAttrs (cfg.user == "cups") {
      cups = {
        inherit (cfg) group;

        description = "CUPS printing services";
      };
    };

    users.groups.lpadmin = { };
    users.groups.lp = lib.mkIf (cfg.group == "lp") { };
  };
}
