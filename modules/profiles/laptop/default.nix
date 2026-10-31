{
  modules,
  config,
  lib,
  ...
}:
let
  cfg = config.profiles.laptop;
  inherit (lib) types;
in
{
  imports = [
    (lib.mkAliasOptionModule
      [ "profiles" "laptop" "hardwareSupport" ]
      [ "profiles" "graphical" "hardwareSupport" ]
    )
  ]
  ++ builtins.attrValues {
    inherit (modules)
      power-profiles-daemon
      brightnessctl
      graphical
      upower
      zzz
      ;
  };

  options.profiles.laptop = {
    enable = lib.mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable an opinionated `finix` profile for a personal laptop. Covers
        the plumbing (init, audio, networking, power, login greeter, ...) so you can focus
        on the bits that vary per machine.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    profiles.graphical.enable = true;

    programs.brightnessctl.enable = lib.mkDefault true;
    programs.zzz.enable = lib.mkDefault true;

    services.power-profiles-daemon.enable = lib.mkDefault true;
    services.power-profiles-daemon.extraGroups = lib.optionals config.services.seatd.enable [
      config.services.seatd.group
    ];
    services.upower.enable = lib.mkDefault true;
    providers.privileges.rules =
      lib.optionals (config.services.seatd.enable && config.programs.zzz.enable)
        [
          {
            command = "/run/current-system/sw/bin/zzz";
            groups = [ config.services.seatd.group ];
            requirePassword = false;
          }
          {
            command = "/run/current-system/sw/bin/ZZZ";
            groups = [ config.services.seatd.group ];
            requirePassword = false;
          }
        ];
  };
}
