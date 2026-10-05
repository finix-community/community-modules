{
  modules,
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.profiles.laptop;
  hasSessionManager = config.services.elogind.enable || config.services.sessiond.enable;
  needsSeatdPrivileges = config.services.seatd.enable && !hasSessionManager;
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

    user = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = ''
        The user to treat as the primary user for this system and configure the access groups needed by the laptop profile.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          config.services.elogind.enable -> config.services.gardendevd.enable || config.services.udev.enable;
        message = "elogind requires either gardendevd or (e)udev; enable one of those device managers.";
      }
      {
        assertion =
          config.services.fwupd.enable
          ->
            (config.services.gardendevd.enable || config.services.udev.enable)
            && config.services.udisks2.enable;
        message = "fwupd requires either gardendevd or (e)udev, and the udisks2 service.";
      }
      {
        assertion =
          config.services.networkmanager.enable
          -> config.services.gardendevd.enable || config.services.udev.enable;
        message = "NetworkManager requires either gardendevd or (e)udev; enable one of those device managers.";
      }
      {
        assertion =
          lib.count (enabled: enabled) [
            config.services.udev.enable
            config.services.gardendevd.enable
            config.services.keventd.enable
            config.services.mdevd.enable
          ] == 1;
        message = "The laptop profile requires exactly one device manager: udev, gardendevd, keventd, or mdevd.";
      }
      {
        assertion = !(config.services.iwd.enable && config.services.networkmanager.enable);
        message = "The laptop profile requires exactly one network manager: iwd or NetworkManager.";
      }
      {
        assertion = !(config.services.elogind.enable && config.services.sessiond.enable);
        message = "Choose one session manager: elogind or sessiond.";
      }
    ];

    boot.kernelParams = [
      "loglevel=1"
    ];

    # graphical runlevel
    finit.runlevel = 3;

    finit.cgroups.system.settings = {
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

    services.keventd.enable = lib.mkDefault (
      !(config.services.mdevd.enable || config.services.gardendevd.enable || config.services.udev.enable)
    );

    # mdevd needs to rebroadcast events for libudev-zero consumers such as the graphical stack
    services.mdevd.nlgroups = lib.mkIf config.services.mdevd.enable (lib.mkDefault 4);

    services.elogind.enable = lib.mkDefault false;
    services.seatd.enable = lib.mkDefault (!config.services.elogind.enable);
    services.sessiond.enable = lib.mkDefault (
      !config.services.mdevd.enable && !config.services.elogind.enable
    );
    services.sessiond-uaccess.enable = lib.mkDefault (
      !config.services.mdevd.enable && !config.services.elogind.enable
    );

    services.iwd.enable = lib.mkDefault (!config.services.networkmanager.enable);

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
    services.fwupd.enable = lib.mkDefault (
      config.services.gardendevd.enable || config.services.udev.enable
    );
    services.getty.package = lib.mkDefault (
      pkgs.util-linuxMinimal
      // {
        meta.mainProgram = "agetty";
      }
    );
    services.nix-daemon.enable = true;
    services.polkit.enable = true;
    services.power-profiles-daemon.enable = lib.mkDefault true;
    services.power-profiles-daemon.extraGroups = lib.optionals needsSeatdPrivileges [
      config.services.seatd.group
    ];
    services.rtkit.enable = lib.mkDefault true;
    services.rtkit.extraGroups = lib.optionals needsSeatdPrivileges [
      config.services.seatd.group
    ];
    services.sysklogd.enable = true;
    services.udisks2.enable = lib.mkDefault (
      config.services.gardendevd.enable || config.services.udev.enable
    );
    services.upower.enable = lib.mkDefault true;
    services.getty.enable = lib.mkDefault true;

    services.nftables.enable = lib.mkDefault true;
    providers.firewall.allowedTCPPorts = [ 22 ]; # sshd

    xdg.autostart.enable = lib.mkDefault true;
    xdg.icons.enable = lib.mkDefault true;
    xdg.mime.enable = lib.mkDefault true;
    xdg.portal.enable = lib.mkDefault true;

    users.users = lib.optionalAttrs (cfg.user != null) {
      ${cfg.user} = {
        isNormalUser = lib.mkDefault true;
        extraGroups = lib.mkAfter (
          lib.optionals (!hasSessionManager) [
            "audio"
            "input"
            "video"
          ]
          ++ lib.optionals config.programs.sudo.enable [ "wheel" ]
          ++ lib.optionals config.services.networkmanager.enable [ "networkmanager" ]
          ++ lib.optionals config.services.seatd.enable [ config.services.seatd.group ]
        );
      };
    };

    providers.privileges.rules =
      lib.optionals needsSeatdPrivileges [
        {
          command = "/run/current-system/sw/bin/poweroff";
          groups = [ config.services.seatd.group ];
          requirePassword = false;
        }
        {
          command = "/run/current-system/sw/bin/reboot";
          groups = [ config.services.seatd.group ];
          requirePassword = false;
        }
      ]
      ++ lib.optionals (needsSeatdPrivileges && config.programs.zzz.enable) [
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
