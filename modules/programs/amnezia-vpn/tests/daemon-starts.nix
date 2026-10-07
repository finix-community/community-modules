# the gui client needs a desktop session, but the module also runs
# AmneziaVPN-service as a system daemon and wires its dbus policy in - none of
# which needs a screen.
{
  machine = {
    services.mdevd.enable = true;

    programs.amnezia-vpn.enable = true;
  };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2", timeout=600)

    with subtest("the daemon is running"):
        machine.wait_until_succeeds("pgrep -f AmneziaVPN-service", timeout=180)

    with subtest("the bus the daemon is wired to is running"):
        # the module puts the package in `services.dbus.packages`, but the
        # package ships no policy of its own - nothing under /etc/dbus-1 comes
        # from it - so all that line buys today is dbus being enabled at all
        machine.wait_until_succeeds("pgrep -x dbus-daemon", timeout=180)

    with subtest("the client and the resolver it depends on are installed"):
        machine.succeed("command -v AmneziaVPN")
        machine.succeed("command -v resolvconf")

    machine.shutdown()
  '';
}
