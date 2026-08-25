# yarr should come up as its own user and serve its web ui.
{
  machine = {
    services.mdevd.enable = true;

    services.yarr.enable = true;
    services.yarr.address = "127.0.0.1";
    services.yarr.port = 7070;
  };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2")

    with subtest("the state directory was created for the service user"):
        machine.wait_until_succeeds("test -d /var/lib/yarr", timeout=180)
        owner = machine.succeed("stat -c %U:%G /var/lib/yarr")
        assert owner.strip() == "yarr:yarr", f"state dir owned by {owner.strip()}"

    with subtest("the web ui answers"):
        machine.wait_for_open_port(7070, timeout=180)
        machine.succeed("curl -sSf http://127.0.0.1:7070/ > /dev/null")

    with subtest("it runs unprivileged"):
        user = machine.succeed("ps -o user= -C yarr | head -n1")
        assert user.strip() == "yarr", f"yarr runs as {user.strip()}"

    machine.shutdown()
  '';
}
