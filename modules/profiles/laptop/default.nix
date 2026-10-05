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
  hasFullDeviceManager = config.services.gardendevd.enable || config.services.udev.enable;
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
        Whether to enable an overridable `finix` profile for a personal laptop. Covers
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

    packages = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ pkgs.nixos-rebuild-ng ];
      defaultText = lib.literalExpression "[ pkgs.nixos-rebuild-ng ]";
      description = ''
        Extra system packages provided by the profile. Set to an empty list to
        omit them without removing packages installed by other modules.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Warn about unusual stacks; finix still enforces its own constraints
    warnings =
      lib.optional (
        config.services.elogind.enable && !hasFullDeviceManager
      ) "laptop: elogind is normally used with udev or gardendevd; verify device access with your stack."
      ++ lib.optional (
        config.services.fwupd.enable && (!hasFullDeviceManager || !config.services.udisks2.enable)
      ) "laptop: fwupd normally uses udev/gardendevd and udisks2; verify your firmware update setup."
      ++ lib.optional (
        config.services.networkmanager.enable && !hasFullDeviceManager
      ) "laptop: NetworkManager's udev integration may need a different package or device manager."
      ++ lib.optional (
        lib.count (enabled: enabled) [
          config.services.udev.enable
          config.services.gardendevd.enable
          config.services.keventd.enable
          config.services.mdevd.enable
        ] != 1
      ) "laptop: normally select one device manager; multiple managers may conflict in core."
      ++ lib.optional (
        config.services.iwd.enable && config.services.networkmanager.enable
      ) "laptop: iwd and NetworkManager are both enabled; configure them not to compete for Wi-Fi."
      ++ lib.optional (
        config.services.elogind.enable && config.services.sessiond.enable
      ) "laptop: elogind and sessiond are both enabled; verify session and power management."
      ++ lib.optional (
        config.services.sessiond-uaccess.enable && !config.services.sessiond.enable
      ) "laptop: sessiond-uaccess waits for sessiond; enable sessiond or disable sessiond-uaccess.";

    # Keep quiet boot alongside core flags; later loglevel values override it.
    boot.kernelParams = lib.mkBefore [
      "loglevel=1"
    ];

    # Start graphically unless the user chooses a different runlevel.
    finit.runlevel = lib.mkDefault 3;

    finit.cgroups.system.settings = {
      "cpu.weight" = lib.mkDefault 100;
    };

    # Cleaning needs a scheduler, not specifically fcron.
    finit.tmpfiles.clean.enable = lib.mkDefault (config.providers.scheduler.backend != "none");

    # Keep core packages when the user omits the profile's tooling.
    environment.systemPackages = cfg.packages;

    fonts.fontconfig.enable = lib.mkDefault true;
    fonts.enableDefaultPackages = lib.mkDefault true;

    hardware.firmware = lib.mkDefault (
      with pkgs;
      [
        linux-firmware
        sof-firmware
        wireless-regdb
      ]
    );

    hardware.graphics.enable = lib.mkDefault true;

    programs.pipewire.enable = lib.mkDefault true;
    # Core requires PipeWire when WirePlumber is enabled.
    programs.wireplumber.enable = lib.mkDefault true;

    programs.bash.enable = lib.mkDefault true;
    programs.brightnessctl.enable = lib.mkDefault true;
    programs.limine.enable = lib.mkDefault true;
    programs.limine.settings.editor_enabled = lib.mkDefault true;
    programs.nano.enable = lib.mkDefault true;
    programs.nano.defaultEditor = lib.mkDefault config.programs.nano.enable;
    programs.plymouth.enable = lib.mkDefault true;
    programs.regreet.enable = lib.mkDefault true;
    programs.resolvconf.enable = lib.mkDefault true;
    programs.sudo.enable = lib.mkDefault true;
    programs.zzz.enable = lib.mkDefault true;

    # An explicit device manager takes precedence over keventd.
    services.keventd.enable = lib.mkDefault (
      !(config.services.mdevd.enable || config.services.gardendevd.enable || config.services.udev.enable)
    );

    # Rebroadcast events for libudev-zero consumers.
    services.mdevd.nlgroups = lib.mkIf config.services.mdevd.enable (lib.mkDefault 4);

    services.elogind.enable = lib.mkDefault false;
    services.seatd.enable = lib.mkDefault (!config.services.elogind.enable);
    services.sessiond.enable = lib.mkDefault (
      !config.services.mdevd.enable && !config.services.elogind.enable
    );
    # Don't leave uaccess waiting for a disabled sessiond.
    services.sessiond-uaccess.enable = lib.mkDefault config.services.sessiond.enable;

    services.iwd.enable = lib.mkDefault (!config.services.networkmanager.enable);

    services.atd.enable = lib.mkDefault true;
    services.bluetooth.enable = lib.mkDefault true;
    services.chrony.enable = lib.mkDefault true;
    # Core services may still enable their required dependencies.
    services.dbus.enable = lib.mkDefault true;
    services.earlyoom.enable = lib.mkDefault true;
    services.earlyoom.extraArgs = lib.mkDefault [
      "-r"
      "3600"
    ];
    services.fcron.enable = lib.mkDefault true;
    services.fwupd.enable = lib.mkDefault (hasFullDeviceManager && config.services.udisks2.enable);
    services.getty.package = lib.mkDefault (
      pkgs.util-linuxMinimal
      // {
        meta.mainProgram = "agetty";
      }
    );
    services.nix-daemon.enable = lib.mkDefault true;
    services.polkit.enable = lib.mkDefault true;
    services.power-profiles-daemon.enable = lib.mkDefault true;
    services.power-profiles-daemon.extraGroups = lib.mkDefault (
      lib.optionals needsSeatdPrivileges [
        config.services.seatd.group
      ]
    );
    services.rtkit.enable = lib.mkDefault true;
    services.rtkit.extraGroups = lib.mkDefault (
      lib.optionals needsSeatdPrivileges [
        config.services.seatd.group
      ]
    );
    services.sysklogd.enable = lib.mkDefault true;
    services.udisks2.enable = lib.mkDefault hasFullDeviceManager;
    services.upower.enable = lib.mkDefault true;
    services.getty.enable = lib.mkDefault true;

    services.nftables.enable = lib.mkDefault true;
    # SSH is optional; users can replace this list with [].
    providers.firewall.allowedTCPPorts = lib.mkDefault [ 22 ];

    xdg.autostart.enable = lib.mkDefault true;
    xdg.icons.enable = lib.mkDefault true;
    xdg.mime.enable = lib.mkDefault true;
    xdg.portal.enable = lib.mkDefault true;

    users.users = lib.optionalAttrs (cfg.user != null) {
      ${cfg.user} = {
        isNormalUser = lib.mkDefault true;
        # An explicit group list replaces these suggested memberships.
        extraGroups = lib.mkDefault (
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

    # Merge with core greeter rules; use mkForce for a complete replacement.
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
