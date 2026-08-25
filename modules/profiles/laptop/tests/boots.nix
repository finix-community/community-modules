# the profile's promise is that enabling it gets you a working laptop without
# assembling the plumbing yourself, so the test is exactly that: turn it on and
# check the machine reaches the graphical runlevel it asks for with the seat,
# device, network, power and logging services it picked all running.
#
# the parts that cannot exist in a vm are forced off below, and only those.
{
  machine =
    { lib, ... }:
    {
      profiles.laptop.enable = true;
      # mdevd + seatd + iwd, which is the lighter of the two stacks
      profiles.laptop.hardwareSupport = "minimal";

      # a test vm boots off a kernel handed to qemu and has no esp to install a
      # bootloader into. the profile sets this one outright, hence mkForce
      programs.limine.enable = lib.mkForce false;
      # both want a display; the profile only defaults these on
      programs.plymouth.enable = false;
      programs.regreet.enable = false;
    };

  testScript = ''
    machine.start()

    with subtest("it boots to the graphical runlevel the profile asks for"):
        machine.wait_for_console_text("entering runlevel 3", timeout=600)

    with subtest("the device and seat managers it picked are running"):
        machine.wait_until_succeeds("pgrep -x mdevd", timeout=180)
        machine.wait_until_succeeds("pgrep -x seatd", timeout=180)
        machine.fail("pgrep -x udevd")

    with subtest("the wifi manager it picked is running"):
        machine.wait_until_succeeds("pgrep -x iwd", timeout=180)

    with subtest("the session plumbing is up"):
        machine.wait_until_succeeds("pgrep -x dbus-daemon", timeout=180)
        machine.wait_until_succeeds("pgrep -x polkitd", timeout=180)
        machine.wait_until_succeeds("pgrep -x syslogd", timeout=180)

    with subtest("power and memory management are up"):
        machine.wait_until_succeeds("pgrep -x earlyoom", timeout=180)
        machine.wait_until_succeeds("pgrep -f power-profiles-daemon", timeout=180)
        machine.wait_until_succeeds("pgrep -x upowerd", timeout=180)

    with subtest("the firewall it ships was loaded"):
        rules = machine.succeed("nft list ruleset")
        assert "policy drop" in rules, rules
        assert "tcp dport" in rules, rules

    with subtest("the tools it puts on PATH are there"):
        machine.succeed("command -v brightnessctl")
        machine.succeed("command -v nano")
        machine.succeed("command -v nixos-rebuild")

    machine.shutdown()
  '';
}
