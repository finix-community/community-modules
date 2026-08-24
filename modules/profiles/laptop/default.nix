{
  modules,
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.profiles.laptop;
in
{
  imports = with modules; [
    atd
    bash
    bluetooth
    brightnessctl
    chronyd
    earlyoom
    fcron
    fwupd
    getty
    greetd
    iwd
    limine
    nano
    networkmanager
    nftables
    nix-daemon
    pipewire
    polkit
    power-profiles-daemon
    regreet
    rtkit
    sessiond-uaccess
    sudo
    sysklogd
    udisks2
    upower
    wireplumber
    zzz
  ];

  options.profiles.laptop = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable an opinionated `finix` profile for a personal laptop. Covers
        the plumbing (init, audio, networking, power, login greeter, ...) so you can focus
        on the bits that vary per machine.
      '';
    };

    devices = lib.mkOption {
      type = lib.types.enum [
        "gardendevd"
        "keventd"
        "mdevd"
        "udev"
      ];
    };

    hardwareSupport = lib.mkOption {
      type = lib.types.enum [
        "full"
        "minimal"
        "standard"
      ];
      default = "standard";
      description = ''
        Determine the level of hardware support and stack desired for this system.

        - `full` - `gardendevd`, `seatd`, `sessiond`, and `NetworkManager`, vs
        - `standard` - `keventd`, `seatd`, `sessiond`, and `iwd`
        - `minimal` - `mdevd`, `seatd`, and `iwd`
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          config.services.fwupd.enable
          ->
            (config.services.gardendevd.enable || config.services.udev.enable)
            && config.services.udisks2.enable;
        message = "fwupd (configured via services.fwupd.enable = true) requires either the gardendevd or (e)udev device manager and the udisks2 service; please set services.gardendevd.enable = true; and services.udisks2.enable = true;";
      }
      {
        assertion =
          config.services.networkmanager.enable
          -> config.services.gardendevd.enable || config.services.udev.enable;
        message = "NetworkManager (configured via services.networkmanager.enable = true) requires either the gardendevd or (e)udev device manager; please set services.gardendevd.enable = true;";
      }
    ];

    boot.kernelParams = [
      "loglevel=1"
    ];

    # graphical runlevel
    finit.runlevel = 3;

    finit.cgroups.system = {
      "cpu.weight" = 100;
    };

    finit.tmpfiles.clean.enable = true;

    environment.systemPackages = [
      pkgs.nixos-rebuild-ng
    ];

    fonts.fontconfig.enable = lib.mkDefault true;
    fonts.enableDefaultPackages = lib.mkDefault true;

    hardware.firmware = with pkgs; [
      linux-firmware
      sof-firmware
      wireless-regdb
    ];

    hardware.graphics.enable = true;

    programs.pipewire.enable = true;
    programs.wireplumber.enable = true;

    programs.bash.enable = true;
    programs.brightnessctl.enable = lib.mkDefault true;
    programs.limine.enable = true;
    programs.limine.settings.editor_enabled = lib.mkDefault true;
    programs.nano.enable = lib.mkDefault true;
    programs.nano.defaultEditor = lib.mkDefault true;
    programs.plymouth.enable = lib.mkDefault true;
    programs.regreet.enable = lib.mkDefault true;
    programs.resolvconf.enable = lib.mkDefault true;
    programs.sudo.enable = lib.mkDefault true;
    programs.zzz.enable = lib.mkDefault true;

    # choose *one* device manager
    services.mdevd.enable = lib.mkIf (cfg.hardwareSupport == "minimal") (lib.mkDefault true);
    services.keventd.enable = lib.mkIf (cfg.hardwareSupport == "standard") (lib.mkDefault true);
    services.gardendevd.enable = lib.mkIf (cfg.hardwareSupport == "full") (lib.mkDefault true);

    # choose *one* seat manager
    services.seatd.enable = lib.mkDefault true;
    services.sessiond.enable = lib.mkIf (cfg.hardwareSupport != "minimal") (lib.mkDefault true);
    services.sessiond-uaccess.enable = lib.mkIf (cfg.hardwareSupport != "minimal") (lib.mkDefault true);

    # choose *one* wifi manager
    services.iwd.enable = lib.mkIf (cfg.hardwareSupport != "full") (lib.mkDefault true);
    services.networkmanager.enable = lib.mkIf (cfg.hardwareSupport == "full") (lib.mkDefault true);

    services.atd.enable = true;
    services.bluetooth.enable = lib.mkDefault true;
    services.chrony.enable = lib.mkDefault true;
    services.dbus.enable = true;
    services.earlyoom.enable = lib.mkDefault true;
    services.earlyoom.extraArgs = [
      "-r"
      "3600"
    ];
    services.fcron.enable = lib.mkDefault true;
    services.fwupd.enable = lib.mkIf (cfg.hardwareSupport == "full") (lib.mkDefault true);
    # services.getty.package = pkgs.util-linuxMinimal // {
    #   meta.mainProgram = "agetty";
    # };
    services.nix-daemon.enable = true;
    services.polkit.enable = true;
    services.power-profiles-daemon.enable = lib.mkDefault true;
    services.rtkit.enable = lib.mkDefault true;
    services.sysklogd.enable = true;
    services.udisks2.enable = lib.mkIf (cfg.hardwareSupport == "full") (lib.mkDefault true);
    services.upower.enable = lib.mkDefault true;
    services.getty.enable = lib.mkDefault true;

    services.nftables.enable = lib.mkDefault true;
    providers.firewall.allowedTCPPorts = [ 22 ]; # sshd

    xdg.autostart.enable = lib.mkDefault true;
    xdg.icons.enable = lib.mkDefault true;
    xdg.mime.enable = lib.mkDefault true;
    xdg.portal.enable = lib.mkDefault true;
  };
}
