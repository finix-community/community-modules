# tailscaled should come up and answer its cli. the node is never logged in -
# that needs an auth key and the real coordination server - so this asserts the
# daemon runs and reports a logged-out state rather than anything about a
# tailnet.
{
  machine = {
    services.mdevd.enable = true;

    services.tailscale.enable = true;
  };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2", timeout=600)

    with subtest("the state and runtime directories exist"):
        machine.wait_until_succeeds("test -d /run/tailscale", timeout=180)
        machine.wait_until_succeeds("test -d /var/lib/tailscale", timeout=180)

    with subtest("the daemon waits for a default route, as its unit declares"):
        # the test network is a static /24 with no gateway, so nothing has
        # satisfied `net/route/default` yet
        machine.fail("pgrep -f tailscaled")
        machine.succeed("ip route add default via 192.168.1.254 dev eth0")

    with subtest("the daemon is running"):
        # the module runs tailscaled through a generated script, so the process
        # is not named plainly after the binary
        machine.wait_until_succeeds("pgrep -f tailscaled", timeout=180)
        machine.wait_until_succeeds("test -S /run/tailscale/tailscaled.sock", timeout=180)

    with subtest("the cli reaches the daemon"):
        machine.succeed("tailscale version")
        status = machine.succeed("tailscale status || true")
        assert "Logged out" in status or "NeedsLogin" in status, f"unexpected status: {status}"

    machine.shutdown()
  '';
}
