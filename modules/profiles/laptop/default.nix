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

    hardwareSupport = lib.mkOption {
      type = lib.types.enum [
        "minimal"
        "standard"
      ];
      default = "standard";
      description = ''
        Determine the level of hardware support and stack desired for this system.

        - `standard` - `udev`, `elogind`, and `NetworkManager`, vs
        - `minimal` - `mdevd`, `seatd`, and `iwd`
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.elogind.enable -> config.services.udev.enable;
        message = "elogind (configured via services.elogind.enable = true) requires the (e)udev device manager; please set services.udev.enable = true;";
      }
      {
        assertion =
          config.services.fwupd.enable -> config.services.udev.enable && config.services.udisks2.enable;
        message = "fwupd (configured via services.fwupd.enable = true) requires the (e)udev device manager and the udisks2 service; please set services.udev.enable = true; and services.udisks2.enable = true;";
      }
      {
        assertion = config.services.networkmanager.enable -> config.services.udev.enable;
        message = "NetworkManager (configured via services.networkmanager.enable = true) requires the (e)udev device manager; please set services.udev.enable = true;";
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
    services.udev.enable = cfg.hardwareSupport == "standard";
    services.mdevd.enable = cfg.hardwareSupport == "minimal";

    # required for graphical environments
    services.mdevd.nlgroups = 4;

    # choose *one* seat manager
    services.elogind.enable = config.services.udev.enable;
    services.seatd.enable = config.services.mdevd.enable;

    # choose *one* wifi manager
    services.iwd.enable = config.services.mdevd.enable;
    services.networkmanager.enable = config.services.udev.enable;

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
    services.fwupd.enable = lib.mkDefault config.services.udev.enable;
    services.nftables.enable = lib.mkDefault true;
    services.nix-daemon.enable = true;
    services.polkit.enable = true;
    services.power-profiles-daemon.enable = lib.mkDefault true;
    services.power-profiles-daemon.extraGroups = lib.optionals config.services.seatd.enable [
      config.services.seatd.group
    ];
    services.rtkit.enable = lib.mkDefault true;
    services.rtkit.extraGroups = lib.optionals config.services.seatd.enable [
      config.services.seatd.group
    ];
    services.sysklogd.enable = true;
    services.udisks2.enable = lib.mkDefault config.services.udev.enable;
    services.upower.enable = lib.mkDefault true;

    # https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes#Simple_IP/IPv6_Firewall
    services.nftables.configFile = pkgs.writeText "nftables.conf" ''
      flush ruleset

      table firewall {
        chain incoming {
          type filter hook input priority 0; policy drop;

          # established/related connections
          ct state established,related accept

          # loopback interface
          iifname lo accept

          # icmp
          icmp type echo-request accept

          # open tcp ports: sshd (22)
          tcp dport { 22 } accept
        }
      }

      table ip6 firewall {
        chain incoming {
          type filter hook input priority 0; policy drop;

          # established/related connections
          ct state established,related accept

          # invalid connections
          ct state invalid drop

          # loopback interface
          iifname lo accept

          # icmp
          # routers may also want: mld-listener-query, nd-router-solicit
          icmpv6 type { echo-request, nd-neighbor-solicit } accept

          # open tcp ports: sshd (22)
          tcp dport { 22 } accept
        }
      }
    '';

    xdg.autostart.enable = lib.mkDefault true;
    xdg.icons.enable = lib.mkDefault true;
    xdg.mime.enable = lib.mkDefault true;
    xdg.portal.enable = lib.mkDefault true;

    providers.privileges.rules =
      lib.optionals config.services.seatd.enable [
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
      ++ lib.optionals (config.services.seatd.enable && config.programs.zzz.enable) [
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
