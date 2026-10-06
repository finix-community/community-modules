# TODO: add missing "good to have" modules:
# - orca
# - geoclue2
# - dconf
# - system76-scheduler
{
  lib,
  pkgs,
  config,
  modules,
  ...
}:
let
  cfg = config.profiles.cosmic-de;
  inherit (lib) types;
in
{
  imports = [
    (lib.mkAliasOptionModule
      [ "profiles" "cosmic-de" "hardwareSupport" ]
      [ "profiles" "graphical" "hardwareSupport" ]
    )
  ]
  ++ builtins.attrValues {
    inherit (modules)
      acpid
      avahi
      power-profiles-daemon
      brightnessctl
      graphical
      gvfs
      gnome-keyring
      upower
      zzz
      ;
  };

  options.profiles.cosmic-de = {
    enable = lib.mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable an opinionated `finix` profile for the COSMIC desktop environment.
        Covers the desktop plumbing so you can focus on the bits that vary per machine.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    profiles.graphical.enable = true;

    environment.pathsToLink = [
      "/share/backgrounds"
      "/share/cosmic"
      "/share/cosmic-layouts"
      "/share/cosmic-themes"
    ];

    programs = {
      cosmic-greeter.enable = lib.mkDefault true;
      cosmic-session.enable = lib.mkDefault true;
      cosmic-term.enable = lib.mkDefault true;
      cosmic-edit.enable = lib.mkDefault true;
      cosmic-osd.enable = lib.mkDefault true;
      cosmic-workspaces-epoch.enable = lib.mkDefault true;
    };

    services = {
      acpid.enable = lib.mkDefault true;
      avahi.enable = lib.mkDefault true;
      gvfs.enable = lib.mkDefault true;
    };

    programs.gnome-keyring.enable = lib.mkDefault true;

    environment.systemPackages = builtins.attrValues {
      inherit (pkgs)
        cosmic-idle
        cosmic-randr
        cosmic-icons
        cosmic-files
        cosmic-player
        cosmic-screenshot
        cosmic-sound-theme
        cosmic-store
        cosmic-monitor
        cosmic-reader
        cosmic-bg
        cosmic-launcher
        pop-launcher
        cosmic-initial-setup
        cosmic-wallpapers
        cosmic-app-library
        pop-icon-theme
        ;
    };

    xdg.portal.portals = builtins.attrValues {
      inherit (pkgs)
        xdg-desktop-portal-cosmic
        xdg-desktop-portal-gtk
        ;
    };
  };
}
