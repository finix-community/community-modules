{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.services.soteria;
in
{
  options.services.soteria = {
    enable = lib.mkEnableOption null // {
      description = ''
        Whether to enable Soteria, a Polkit authentication agent
        for any desktop environment.

        ::: {.note}
        You should only enable this if you are on a Desktop Environment that
        does not provide a graphical polkit authentication agent, or you are on
        a standalone window manager or Wayland compositor.
        :::

        ::: {.note}
        Soteria registers itself against your login session, so it has to run
        *inside* one - it needs `XDG_SESSION_ID` in its environment, which only
        a real login session has. This option installs it and points it at the
        right Polkit helper, but does not start it: there is no
        desktop-environment-agnostic way to launch a per-session agent on
        finix, the same way there is no such thing on any other distribution
        either. Start it yourself from wherever your session already starts
        other session programs - for example, in `programs.<compositor>.init`.
        :::
      '';
    };
    package = lib.mkPackageOption pkgs "soteria" { };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    assertions = [
      {
        assertion = config.services.elogind.enable && config.services.polkit.enable;
        message = "`services.elogind.enable` and `services.polkit.enable must both be set to true for soteria to function.";
      }
    ];

    # soteria's compiled-in helper path comes from the polkit it happened to be
    # built against, which is not necessarily the one `services.polkit`
    # actually deploys here (e.g. its `useSystemd` override changes the
    # derivation, and so the path). point it at the wrapper that module
    # installs instead, which is what is really on disk and setuid.
    environment.etc."soteria/config.toml".text = ''
      helper_path = "${config.security.wrapperDir}/polkit-agent-helper-1"
      socket_path = "/run/polkit/agent-helper.socket"
    '';
  };
}
