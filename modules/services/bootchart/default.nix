{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.bootchart;

  format = pkgs.formats.keyValue { };
  configDir = pkgs.writeTextDir "bootchartd.conf" (lib.generators.toKeyValue { } cfg.settings);
  stage2Init = pkgs.writeShellScript "stage2-init" ''
    exec -a "''${INIT_ARGV0:-${config.finit.package}/bin/finit}" ${config.finit.package}/bin/finit "$@"
  '';
in
{
  options.services.bootchart = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable [bootchartd](${cfg.package.meta.homepage}) as a system service.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.initviz";
      description = ''
        The package to use for `bootchartd`.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = format.type;
        options = {
          SAMPLE_HZ = lib.mkOption {
            type = lib.types.ints.positive;
            default = 50;
            description = ''
              Sampling frequency (samples / second).
            '';
          };

          BOOTLOG_DEST = lib.mkOption {
            type = lib.types.str;
            default = "/var/log/bootchart.tgz";
            description = ''
              Tarball for the various boot log files.
            '';
          };

          EXIT_PROC = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = ''
              The processes we have to wait for.
            '';
          };
        };
      };
      default = { };
      description = ''
        `bootchartd` configuration. See [upstream documentation](https://github.com/finit-project/InitViz/blob/main/bootchartd.conf)
        for additional details.
      '';
    };

    stop = {
      runlevel = lib.mkOption {
        type = lib.types.ints.between 0 9;
        default = config.finit.runlevel;
        defaultText = lib.literalExpression "config.finit.runlevel";
        description = ''
          At which runlevel to stop collection.
        '';
      };

      conditions = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        example = [ "service/greetd/ready" ];
        description = ''
          `finit` conditions that must be satisfied before collection is
          stopped. Leave empty to stop as soon as {option}`stop.runlevel` is
          entered.
        '';
      };
    };

    profileKernel = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to include the kernel's boot phase in the profile, in addition to userspace.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelParams = lib.mkIf cfg.profileKernel [
      "printk.time=y"
      "initcall_debug"
    ];

    boot.init = pkgs.writeShellScript "bootchart-init" ''
      export INIT_ARGV0="$0"
      export bootchart_init=${stage2Init}

      cd ${configDir}
      exec ${cfg.package}/bin/bootchartd "$@"
    '';

    environment.etc."bootchartd.conf".source = "${configDir}/bootchartd.conf";
    environment.systemPackages = [ cfg.package ];

    finit.tasks.bootchart-stop = {
      inherit (cfg.stop) conditions;

      description = "stop bootchart collector and write boot chart";
      command = "${cfg.package}/bin/bootchartd stop";
      runlevels = toString cfg.stop.runlevel;
    };
  };
}
