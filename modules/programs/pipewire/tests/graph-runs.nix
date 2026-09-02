# pipewire needs no sound card to run - with no devices it simply has an empty
# graph - so the daemon, the session manager and the configuration this module
# generates can all be checked on a headless machine.
{
  # this module is an alternative to the pipewire module finix ships, so that
  # one is taken out of the host - two declarations of `programs.pipewire` would
  # just be an eval error.
  replacesFinixModules = [ "programs/pipewire" ];

  machine = {
    services.mdevd.enable = true;
    services.dbus.enable = true;

    users.users.compat = {
      isNormalUser = true;
      home = "/home/compat";
      createHome = true;
    };

    programs.pipewire.enable = true;
    programs.pipewire.wireplumber.enable = true;
    programs.pipewire.extraConfig.pipewire."99-compat" = {
      "context.properties"."log.level" = 2;
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2", timeout=600)

    with subtest("the module's configuration was installed"):
        machine.succeed("test -e /etc/pipewire/pipewire.conf.d/99-compat.conf")
        machine.succeed("grep -q 'log.level' /etc/pipewire/pipewire.conf.d/99-compat.conf")

    # pipewire is a user daemon: it wants a runtime directory to put its socket
    # in, which on a real system a login manager provides
    machine.succeed("mkdir -p /run/user/1000 && chown compat: /run/user/1000")
    as_user = lambda cmd: f"su compat -c {('XDG_RUNTIME_DIR=/run/user/1000 ' + cmd)!r}"

    machine.succeed(as_user("pipewire") + " >/tmp/pipewire.log 2>&1 &")

    with subtest("the daemon comes up and creates its socket"):
        machine.wait_until_succeeds("test -S /run/user/1000/pipewire-0", timeout=180)
        machine.wait_until_succeeds("pgrep -u compat -x pipewire", timeout=180)

    with subtest("a client can talk to the graph"):
        info = machine.succeed(as_user("pw-cli info 0"))
        assert "core.name" in info or "PipeWire" in info, info

    machine.succeed(as_user("wireplumber") + " >/tmp/wireplumber.log 2>&1 &")

    with subtest("the session manager attaches to it"):
        machine.wait_until_succeeds("pgrep -u compat -x wireplumber", timeout=180)
        status = machine.succeed(as_user("wpctl status"))
        assert "Audio" in status, status

    machine.shutdown()
  '';
}
