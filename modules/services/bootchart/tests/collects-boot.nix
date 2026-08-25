# bootchart replaces `boot.init`, so getting this wrong costs you the boot
# entirely. the test asserts the machine still reaches runlevel 2 and that the
# collector produced a chart on the way.
{
  machine = {
    services.mdevd.enable = true;

    services.bootchart.enable = true;
    services.bootchart.settings.BOOTLOG_DEST = "/var/log/bootchart.tgz";
  };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2")

    with subtest("the collector config reached /etc"):
        machine.succeed("test -f /etc/bootchartd.conf")

    with subtest("the stop task wrote a chart"):
        machine.wait_until_succeeds("test -s /var/log/bootchart.tgz", timeout=180)

    machine.shutdown()
  '';
}
