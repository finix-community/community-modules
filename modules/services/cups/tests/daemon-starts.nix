# cupsd should start, lay down its state directories, and answer on the ipp
# port. no printer is attached, so this stops at "the daemon is alive and
# listening".
{
  machine = {
    services.mdevd.enable = true;

    services.cups.enable = true;
  };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2")

    with subtest("tmpfiles laid down the state directories"):
        for d in ["/etc/cups", "/run/cups", "/var/lib/cups", "/var/spool/cups"]:
            machine.wait_until_succeeds(f"test -d {d}", timeout=180)
        machine.succeed("test -f /etc/cups/cupsd.conf")

    with subtest("the daemon answers on the ipp port"):
        machine.wait_for_open_port(631, timeout=180)
        machine.succeed("curl -sSf http://127.0.0.1:631/ > /dev/null")

    with subtest("lpstat talks to it"):
        machine.succeed("lpstat -r")

    machine.shutdown()
  '';
}
