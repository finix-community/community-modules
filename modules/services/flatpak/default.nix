{
  config,
  lib,
  modules,
  pkgs,
  ...
}:
let
  cfg = config.services.flatpak;

  # flatpak keyfiles write lists as `a;b`
  ini = pkgs.formats.ini { listToValue = lib.concatStringsSep ";"; };

  overrides = pkgs.linkFarm "flatpak-overrides" (lib.mapAttrs ini.generate cfg.overrides);

  install = pkgs.writeShellScript "flatpak-install" ''
    set -eu
    flatpak="${lib.getExe cfg.package} --system"
    state=/var/lib/flatpak/declarative-packages
    wanted=${lib.escapeShellArg " ${toString cfg.packages} "}
    read -r prev 2>/dev/null < "$state" || prev=

    # stdout is only flatpak's progress bars, which would flood the log
    # so limit log to stderr
    exec > /dev/null
    log() { echo "$*" >&2; }

    install_missing() {
        $flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || return 1
        for app in $wanted; do
            $flatpak info "$app" 2> /dev/null && continue
            log "installing $app"
            $flatpak install -y flathub "$app" || return 1
        done
    }

    # the network may be down at boot or drop mid-download
    until install_missing; do ${lib.getExe' config.programs.coreutils.package "sleep"} 30; done

    # what may be removed: everything installed, or only what the previous run declared
    owned=$prev
    ${lib.boolToString cfg.uninstallUnmanaged} &&
      owned=$($flatpak list --app --columns=application)

    for app in $owned; do
      case "$wanted" in
        *" $app "*) ;;
        *) log "uninstalling $app"; $flatpak uninstall -y "$app" ;;
      esac
    done
    $flatpak uninstall -y --unused

    echo "$wanted" > "$state"
  '';
in
{
  # extends finix's flatpak, which provides `enable`, `package` and the dbus/polkit setup
  imports = [ modules.flatpak ];

  options.services.flatpak = {
    packages = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      example = [
        "com.github.tchx84.Flatseal"
        "md.obsidian.Obsidian"
      ];
      description = ''
        Applications, by application ID, to install system-wide from [flathub](https://flathub.org).
        Applications removed from this list are uninstalled. Updating is left to `flatpak update`.
      '';
    };

    overrides = lib.mkOption {
      type = lib.types.attrsOf ini.type;
      default = { };
      example = lib.literalExpression ''
        {
          global.Environment.XCURSOR_PATH = "/run/host/user-share/icons:/run/host/share/icons";

          "com.usebottles.bottles".Context.filesystems = [
            "xdg-data/applications:create"
            "xdg-desktop:create"
          ];
        }
      '';
      description = ''
        System-wide overrides, keyed by application ID, or `global` for all applications.
        See {manpage}`flatpak-override(1)` and {manpage}`flatpak-metadata(5)` for the available keys.

        ::: {.note}
        Overrides are read-only, `flatpak override --system` will fail. Per-user overrides, such as
        those written by Flatseal, still apply on top.
        :::
      '';
    };

    uninstallUnmanaged = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to also uninstall system-wide applications that are not listed in
        {option}`services.flatpak.packages`, such as ones installed by hand.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    finit.tmpfiles.rules = lib.optional (
      cfg.overrides != { }
    ) "L+ /var/lib/flatpak/overrides - - - - ${overrides}";

    # remain-after-exit: run once at boot, and again on reload only when the script changed
    finit.tasks.flatpak-install = {
      description = "install flatpak applications";
      conditions = "service/syslogd/ready";
      command = install;
      log = true;
      remain-after-exit = true;
    };
  };
}
