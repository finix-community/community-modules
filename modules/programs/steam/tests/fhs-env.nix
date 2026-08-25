# steam itself needs a gpu and a login, but the machinery this module sets up
# around it does not: the fhs environment steam runs inside, the 32-bit driver
# path it needs to render, and the udev rules for its controllers.
#
# this is the most expensive test in the suite - the closure includes the 32-bit
# graphics stack - so it stops at "the environment works", without launching the
# client.
{
  machine = {
    # steam's controller rules need a udev-compatible device manager, which the
    # module's own option documentation calls out
    services.udev.enable = true;

    programs.steam.enable = true;
    programs.steam.hardware.enable = true;
  };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2", timeout=600)

    with subtest("steam and its fhs runner are installed"):
        machine.succeed("command -v steam")
        machine.succeed("command -v steam-run")

    with subtest("the fhs environment actually runs a program"):
        machine.succeed("steam-run true")
        out = machine.succeed("steam-run /bin/sh -c 'echo inside-fhs; ls /usr/lib > /dev/null'")
        assert "inside-fhs" in out, out

    with subtest("the 32-bit driver path steam needs exists"):
        machine.succeed("test -e /run/opengl-driver-32")
        machine.succeed("test -e /run/opengl-driver")

    with subtest("the controller rules were installed"):
        machine.succeed("ls /etc/udev/rules.d/ | grep -qi steam")

    machine.shutdown()
  '';
}
