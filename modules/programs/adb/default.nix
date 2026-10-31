{
  config,
  lib,
  pkgs,
  ...
}:

{
  # interface
  options = {
    programs.adb = {
      enable = lib.mkOption {
        default = false;
        type = lib.types.bool;
        description = ''
          Whether to configure system to use Android Debug Bridge (adb).
          To grant access to a user, it must be part of adbusers group:
          `users.users.alice.extraGroups = ["adbusers"];`
        '';
      };
    };
  };

  # implementation
  config = lib.mkIf config.programs.adb.enable {
    services.udev.packages = [
      (pkgs.callPackage ./android-udev-rules.nix { })
    ];
    environment.systemPackages = [ pkgs.android-tools ];
    users.groups.adbusers = { };
  };
}
