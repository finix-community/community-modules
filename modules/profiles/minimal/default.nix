{
  modules,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.minimal;
in
{
  imports = with modules; [
    bash
    dhcpcd
    getty
    nix-daemon
    sysklogd
  ];

  options.profiles.minimal = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable a minimal `finix` profile for a headless/server machine.
        Covers the bare plumbing (device manager, networking, logging, nix daemon) so
        you can focus on the bits that vary per machine.
      '';
    };
    deviceManager = lib.mkOption {
      type = lib.types.enum [
        "keventd"
        "mdevd"
        "udev"
        "gardendevd"
      ];
      description = ''
        Determine the device manager to use.

        - `udev`  — full-featured, matches the rest of the nix ecosystem (default)
        - `mdevd` — lighter, from the skarnet/s6 family, no systemd code
        - `keventd` — brand new, rule compatible.
      '';
    };
    withFlakes = lib.mkOption {
      type = lib.types.bool;
      description = ''
        Whether to enable flakes for the profile.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.nixos-rebuild-ng
    ];

    programs.bash.enable = true;

    services.dhcpcd.enable = true;

    services.nix-daemon.enable = true;
    services.nix-daemon.settings = {
      experimental-features = lib.mkIf cfg.withFlakes [
        "nix-command"
        "flakes"
      ];
      trusted-users = lib.mkIf config.programs.sudo.enable [
        "root"
        "@wheel"
      ];
    };

    services.sysklogd.enable = true;

    services.${cfg.deviceManager}.enable = true;
  };
}
