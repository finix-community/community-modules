# no rgb controller exists in a vm, but the sdk server does not need one to
# come up and accept clients - which is the part the module is responsible for.
{
  machine = {
    services.mdevd.enable = true;

    services.hardware.openrgb.enable = true;
    services.hardware.openrgb.server.port = 6742;
  };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2", timeout=600)

    with subtest("the module asked for the i2c interface"):
        machine.succeed("grep -qw i2c_dev /proc/modules")

    with subtest("the sdk server is running and listening"):
        # the package is qt-wrapped, so the process is `.openrgb-wrapped`
        machine.wait_until_succeeds("pgrep -f 'openrgb.*--server'", timeout=180)
        machine.wait_for_open_port(6742, timeout=180)

    with subtest("it answers a client"):
        # no controllers are attached, so an empty list is the right answer
        devices = machine.succeed("openrgb --client 127.0.0.1:6742 --list-devices || true")
        assert "Segmentation" not in devices, devices

    machine.shutdown()
  '';
}
