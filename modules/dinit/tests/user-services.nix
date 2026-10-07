# dinit as a user service manager
#
# finit is pid 1 on a finix host, so dinit's job here is the per-user session:
# the module writes `dinit.user.services` to /etc/dinit.d/user, which is one of
# the directories `dinit --user` searches. this boots a host, starts dinit as an
# unprivileged user, and checks it actually supervises what the module wrote.
{
  machine =
    { pkgs, ... }:
    {
      services.mdevd.enable = true;

      users.users.compat = {
        isNormalUser = true;
        home = "/home/compat";
        createHome = true;
      };

      # the module writes service descriptions but does not install dinit, so a
      # host using it has to bring the package along itself
      environment.systemPackages = [ pkgs.dinit ];

      dinit.user.services.compat-probe = {
        type = "scripted";
        command = toString (
          pkgs.writeShellScript "compat-probe-start" ''
            echo "started by dinit" > /home/compat/compat-probe.marker
          ''
        );
      };

      dinit.user.services.compat-daemon = {
        type = "process";
        command = "${pkgs.coreutils}/bin/sleep 3600";
        restart = true;
        environment.COMPAT_PROBE = "set-by-dinit";
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2", timeout=600)

    # the socket lives in the user's own home: whether a session ever got an
    # XDG_RUNTIME_DIR is a login manager's business, not dinit's, and /tmp is
    # not writable by an unprivileged user on this host
    socket = "/home/compat/dinitctl"
    as_user = lambda cmd: f"su compat -c {cmd!r}"

    with subtest("the module wrote user services where dinit looks for them"):
        machine.succeed("test -f /etc/dinit.d/user/compat-probe")
        machine.succeed("test -f /etc/dinit.d/user/compat-daemon")
        machine.succeed("grep -q '^type = process$' /etc/dinit.d/user/compat-daemon")
        # system services would go to /etc/dinit.d, and none were declared here
        machine.fail("test -e /etc/dinit.d/compat-daemon")

    # dinit's own output is kept so a failure below has something to point at
    machine.succeed(
        as_user(f"dinit --user --socket-path {socket} compat-probe compat-daemon")
        + " >/tmp/dinit.log 2>&1 &"
    )

    with subtest("it runs a scripted service"):
        machine.wait_until_succeeds(
            "test -f /home/compat/compat-probe.marker || { cat /tmp/dinit.log >&2; false; }",
            timeout=180,
        )
        content = machine.succeed("cat /home/compat/compat-probe.marker")
        assert "started by dinit" in content, f"unexpected marker content: {content!r}"

    # dinit execs the command as written, so the process is named after its
    # store path rather than `sleep`; match on the command line instead
    daemon_pid = "pgrep -u compat -f 'bin/sleep 3600'"

    with subtest("it supervises a process service, as the user"):
        machine.wait_until_succeeds(
            as_user(f"dinitctl --socket-path {socket} is-started compat-daemon"), timeout=180
        )
        pid = machine.succeed(daemon_pid).strip()
        owner = machine.succeed(f"ps -o user= -p {pid}")
        assert owner.strip() == "compat", f"the service runs as {owner.strip()}"

    with subtest("the environment the module generated reached the process"):
        env = machine.succeed(f"tr '\\0' '\\n' < /proc/{pid}/environ")
        assert "COMPAT_PROBE=set-by-dinit" in env, f"env-file was not applied: {env!r}"

    with subtest("it restarts a process service that dies"):
        machine.succeed(f"kill -9 {pid}")
        machine.wait_until_succeeds(f'test "$({daemon_pid})" != {pid}', timeout=180)
        machine.succeed(as_user(f"dinitctl --socket-path {socket} is-started compat-daemon"))

    machine.shutdown()
  '';
}
