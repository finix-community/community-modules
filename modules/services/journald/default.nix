{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.services.journald;
  inherit (lib) types;
in
{
  options.services.journald = {
    enable = lib.mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable [journald](${pkgs.systemd.meta.homepage}).
      '';
    };
    systemdPackage = lib.mkOption {
      type = types.package;
      default = config.systemd.package or pkgs.systemd;
      defaultText = lib.literalExpression "config.systemd or pkgs.systemd";
      description = ''
        The systemd package to use.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    finit.services.journald = {
      description = "Journal service";
      command = "${cfg.systemdPackage}/lib/systemd/systemd-journald";
      conditions = [ "task/tmpfiles-setup/success" ];
      notify = "systemd";
    };

    finit.tasks.journal-flush = {
      description = "Flush the journal to persistent storage";
      conditions = [ "service/journald/ready" ];
      command = "${cfg.systemdPackage}/bin/journalctl --flush";
    };

    users.groups.systemd-journal = { };

    finit.tmpfiles.rules = [
      "d /run/log/journal 2755 root systemd-journal -"
      "d /var/log/journal 2755 root systemd-journal -"
    ];

    # TODO: make configurable
    environment.etc."systemd/journald.conf".text = ''
      [Journal]
      Storage=persistent
      SplitMode=uid
    '';
  };
}
