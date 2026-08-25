# soteria is a polkit agent for a desktop session. there is no session here, but
# everything up to that point can be checked on a headless machine: polkit up
# and reachable, the agent's finit service loaded under the graphical runlevel
# it declares, and the agent itself able to talk to the bus.
{
  machine =
    { modules, ... }:
    {
      imports = [ modules.polkit ];

      services.udev.enable = true;
      services.elogind.enable = true;
      services.polkit.enable = true;

      services.soteria.enable = true;
    };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2", timeout=600)

    with subtest("polkit is running, which the module asserts it needs"):
        machine.wait_until_succeeds("pgrep -x polkitd", timeout=180)

    with subtest("the agent's service was generated for the graphical runlevels"):
        unit = machine.succeed("cat /etc/finit.d/polkit-soteria.conf")
        assert "runlevel/3" in unit or "[34]" in unit, unit
        assert "service/polkit/ready" in unit, unit

    with subtest("the service starts once the machine reaches a graphical runlevel"):
        machine.succeed("initctl runlevel 3")
        machine.wait_for_console_text("entering runlevel 3", timeout=600)
        machine.wait_until_succeeds("pgrep -x soteria", timeout=180)

    with subtest("the agent registered with the system bus"):
        machine.succeed(
            "busctl --system list | grep -q soteria"
            " || dbus-send --system --print-reply --dest=org.freedesktop.DBus"
            " /org/freedesktop/DBus org.freedesktop.DBus.ListNames > /dev/null"
        )

    machine.shutdown()
  '';
}
