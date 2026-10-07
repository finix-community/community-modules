# preservation does its work from the initrd, before switch_root, so that the
# bind mounts are already in place when stage 2 starts. that is what this
# checks: a volume mounted for boot, and the declared paths pointing into it by
# the time the machine is up.
#
# the volume is a tmpfs rather than a second disk - the test driver gives a vm
# one disk and a 9p store - so this cannot show state surviving a power cycle.
# what it does show is the mechanism: the initrd task ran, under the right mount
# conditions, and everything written to a preserved path lands on the volume.
{
  machine = {
    services.mdevd.enable = true;

    fileSystems."/persist" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "mode=755" ];
      neededForBoot = true;
    };

    preservation.enable = true;
    preservation.preserveAt."/persist" = {
      directories = [
        "/var/lib/compat"
        {
          directory = "/var/lib/compat-link";
          how = "symlink";
        }
      ];
      files = [ "/etc/compat-state" ];
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2", timeout=600)

    with subtest("the volume was mounted for boot"):
        machine.succeed("mountpoint -q /persist")

    with subtest("a preserved directory is a bind mount of the volume"):
        machine.succeed("mountpoint -q /var/lib/compat")
        machine.succeed("test -d /persist/var/lib/compat")

    with subtest("writes through a preserved directory land on the volume"):
        machine.succeed("echo written-through > /var/lib/compat/marker")
        content = machine.succeed("cat /persist/var/lib/compat/marker")
        assert content.strip() == "written-through", f"got {content.strip()!r}"

    with subtest("a symlinked directory points at the volume"):
        target = machine.succeed("readlink /var/lib/compat-link")
        assert target.strip() == "/persist/var/lib/compat-link", f"points at {target.strip()!r}"

    with subtest("a preserved file is a bind mount of the volume"):
        machine.succeed("echo file-state > /etc/compat-state")
        content = machine.succeed("cat /persist/etc/compat-state")
        assert content.strip() == "file-state", f"got {content.strip()!r}"

    machine.shutdown()
  '';
}
