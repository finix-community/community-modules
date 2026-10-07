# `clean.enable` doesn't run gc itself - it registers a task with
# `providers.scheduler`, and does nothing unless the host also picks a
# backend. this picks cron, the simplest one, and checks the task landed in
# its crontab the way the module intends.
{
  machine =
    { modules, ... }:
    {
      imports = [
        modules.cron
        modules.sysklogd
      ];

      services.mdevd.enable = true;

      # cron's finit service gates on `service/syslogd/ready`, which is off by
      # default
      services.sysklogd.enable = true;

      providers.scheduler.backend = "cron";
      services.cron.enable = true;

      programs.nh.enable = true;
      programs.nh.clean.enable = true;
      programs.nh.clean.dates = "daily";
      programs.nh.clean.extraArgs = "--keep 5 --keep-since 3d";
    };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2", timeout=600)

    with subtest("cron is running, which the task needs"):
        machine.wait_until_succeeds("initctl status cron | grep -q running", timeout=180)

    with subtest("the clean task landed in the crontab"):
        crontab = machine.succeed("cat /etc/crontab")
        assert "0 0 * * *" in crontab, crontab
        assert "nh clean all --keep 5 --keep-since 3d" in crontab, crontab

    machine.shutdown()
  '';
}
