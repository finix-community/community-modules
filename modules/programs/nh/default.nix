{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nh;
in
{
  options.programs.nh = {
    enable = lib.mkEnableOption "nh, yet another Nix CLI helper";

    package = lib.mkPackageOption pkgs "nh" { };

    flake = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The string that will be used for the `NH_FLAKE` environment variable.

        `NH_FLAKE` is used by nh as the default flake for performing actions, such as
        `nh os switch`. This behaviour can be overriden per-command with environment
        variables that will take priority.

        - `NH_OS_FLAKE`: will take priority for `nh os` commands.
        - `NH_HOME_FLAKE`: will take priority for `nh home` commands.
        - `NH_DARWIN_FLAKE`: will take priority for `nh darwin` commands.

        The formerly valid `FLAKE` is now deprecated by nh, and will cause hard errors
        in future releases if `NH_FLAKE` is not set.
      '';
    };

    clean = {
      enable = lib.mkEnableOption "periodic garbage collection with nh clean all";

      dates = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "weekly";
        description = ''
          How often cleanup is performed. Passed to providers.scheduler
        '';
      };

      extraArgs = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "";
        example = "--keep 5 --keep-since 3d";
        description = ''
          Options given to nh clean when the service is run automatically.

          See `nh clean all --help` for more information.
        '';
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = (cfg.flake != null) -> !(lib.hasSuffix ".nix" cfg.flake);
        message = "nh.flake must be a directory, not a nix file";
      }
    ];

    environment = lib.mkIf cfg.enable {
      systemPackages = [ cfg.package ];
      variables = lib.mkIf (cfg.flake != null) {
        NH_FLAKE = cfg.flake;
      };
    };

    providers.scheduler = {
      backend = lib.mkDefault "cron";
      tasks.nh-clean = {
        command = "exec ${lib.getExe cfg.package} clean all ${cfg.clean.extraArgs}";
        interval = cfg.clean.dates;  
      };
    };
  };
}
