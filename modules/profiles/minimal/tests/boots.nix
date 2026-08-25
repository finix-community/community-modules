# the minimal profile is meant to be enough to boot a headless machine on its
# own, so the test is exactly that: enable it and nothing else, and check the
# pieces it promises are there.
{
  machine =
    { modules, ... }:
    {
      # the profile configures these but does not import them, so a host using
      # it has to bring them along.
      imports = [
        modules.bash
        modules.dhcpcd
        modules.nix-daemon
        modules.sudo
        modules.sysklogd
      ];

      profiles.minimal.enable = true;
      # neither of these has a default; the profile makes you choose
      profiles.minimal.deviceManager = "udev";
      profiles.minimal.withFlakes = true;
    };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2")

    with subtest("a shell is available"):
        machine.succeed("test -x /run/current-system/sw/bin/bash")

    with subtest("the nix daemon is configured and running"):
        machine.wait_until_succeeds("pgrep -f nix-daemon", timeout=180)
        machine.succeed("grep -q experimental-features /etc/nix/nix.conf")

    with subtest("syslog is collecting"):
        machine.wait_until_succeeds("pgrep -x syslogd", timeout=180)

    with subtest("dhcpcd is managing the network"):
        machine.wait_until_succeeds("pgrep -x dhcpcd", timeout=180)

    machine.shutdown()
  '';
}
