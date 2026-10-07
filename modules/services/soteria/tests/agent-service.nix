# soteria is a gtk4 app: registering against a login session (below) gets it
# past its own checks, but gtk itself still refuses to initialize with no
# display behind it. wlroots has a headless backend, so a bare compositor -
# just the plain river package, not `programs.river` - gives it one without
# needing a gpu or a seat. river isn't what's under test here, it's only the
# smallest thing on hand that can hand gtk a wayland display.
{
  machine =
    {
      modules,
      lib,
      pkgs,
      config,
      ...
    }:
    {
      imports = [
        modules.polkit
        modules.autologin
      ];

      services.mdevd.enable = true;
      services.elogind.enable = true;
      services.polkit.enable = true;

      # dbus-run-session's private bus socket lands under /tmp, and the
      # driver's root is a fresh tmpfs where /tmp ends up mode 755
      fileSystems."/tmp" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "mode=1777" ];
      };

      services.soteria.enable = true;

      users.users.compat = {
        isNormalUser = true;
        home = "/home/compat";
        createHome = true;
      };

      services.autologin.enable = true;
      services.autologin.user = "compat";
      services.autologin.command = pkgs.writeShellScript "compat-session" ''
        exec >"$HOME/session.log" 2>&1
        export WLR_BACKENDS=headless
        export WLR_LIBINPUT_NO_DEVICES=1
        exec ${pkgs.dbus}/bin/dbus-run-session -- ${lib.getExe pkgs.river} -c ${pkgs.writeShellScript "compat-init" ''
          ${lib.getExe config.services.soteria.package} >"$HOME/soteria.log" 2>&1 &
          touch "$HOME/session-started"
        ''}
      '';
    };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2", timeout=600)

    with subtest("polkit is running, which the module asserts it needs"):
        machine.wait_until_succeeds("pgrep -x polkitd", timeout=180)

    with subtest("autologin gave the agent a real session, with a real display, to run in"):
        machine.wait_until_succeeds(
            "test -e /home/compat/session-started"
            " || { cat /home/compat/session.log >&2; false; }",
            timeout=180,
        )

    with subtest("soteria stayed up, which means it got a session, a helper and a display"):
        # nixpkgs wraps it with wrapGAppsHook4, so /proc/[pid]/comm is the
        # (kernel-truncated) wrapped-binary name, not "soteria" - match the
        # command line instead, the same way the tailscale and openrgb tests
        # do for their own wrapped/scripted binaries
        machine.wait_until_succeeds(
            "pgrep -u compat -f bin/soteria"
            " || { cat /home/compat/soteria.log >&2; false; }",
            timeout=180,
        )

    with subtest("the agent registered with the system bus"):
        machine.succeed(
            "busctl --system list | grep -q soteria"
            " || dbus-send --system --print-reply --dest=org.freedesktop.DBus"
            " /org/freedesktop/DBus org.freedesktop.DBus.ListNames > /dev/null"
        )

    machine.shutdown()
  '';
}
