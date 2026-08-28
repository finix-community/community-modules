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

        `NH_FLAKE` can point to either a folder containing a flake, or to an outside repository containing the flake.
      '';
    };

    clean = {
      enable = lib.mkEnableOption "periodic garbage collection with nh clean all";

      dates = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "weekly";
        description = ''
          How often `nh clean` is performed. Accepts either a standard {manpage}`crontab(5)` expression
          or one of: `hourly`, `daily`, `weekly`, `monthly`, or `yearly`.

          If a standard {manpage}`crontab(5)` expression is provided this value will be passed directly
          to the `scheduler` implementation and execute exactly as specified.

          If one of the special values, `hourly`, `daily`, `monthly`, `weekly`, or `yearly`, is provided then the
          underlying `scheduler` implementation will use its features to decide when best to run.
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
        message = "nh.flake must be a directory, or valid repository, not a nix file.";
      }
    ];

    environment = lib.mkIf cfg.enable {
      systemPackages = [ cfg.package ];
      variables = lib.mkIf (cfg.flake != null) {
        NH_FLAKE = cfg.flake;
      };
    };

    providers.scheduler.tasks.nh-clean = lib.mkIf cfg.clean.enable {
      command = "${lib.getExe cfg.package} clean all ${cfg.clean.extraArgs}";
      interval = cfg.clean.dates;
    };
  };
}
