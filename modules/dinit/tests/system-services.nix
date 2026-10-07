# `dinit.services` - the system half of the module
#
# these land in /etc/dinit.d, where a dinit running as the *system* service
# manager finds them. finix runs finit as pid 1, so dinit cannot be that here -
# but dinit's container mode is exactly "be the system service manager without
# managing the system", which is enough to load these descriptions and supervise
# what they name.
#
# see tests/user-services.nix for the half a finix host actually runs.
{
  machine =
    { pkgs, ... }:
    {
      services.mdevd.enable = true;

      # the module writes service descriptions but does not install dinit
      environment.systemPackages = [ pkgs.dinit ];

      users.users.compat-svc = {
        isSystemUser = true;
        group = "compat-svc";
      };
      users.groups.compat-svc = { };

      dinit.services.compat-system-probe = {
        type = "process";
        command = "${pkgs.coreutils}/bin/sleep 3600";
        # run-as is the system-only option the module adds on top of the shared
        # ones, so it is the interesting one to check
        run-as = "compat-svc";
        restart = true;
        environment.COMPAT_PROBE = "set-by-dinit";
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2", timeout=600)

    with subtest("the module wrote system services where a system dinit looks"):
        machine.succeed("test -f /etc/dinit.d/compat-system-probe")
        machine.succeed("grep -q '^run-as = compat-svc$' /etc/dinit.d/compat-system-probe")
        # user services would go to /etc/dinit.d/user, and none were declared
        machine.fail("test -e /etc/dinit.d/user/compat-system-probe")

    # container mode: system service manager, without trying to be pid 1
    socket = "/run/dinitctl-system"
    machine.succeed(
        f"dinit --system --container --socket-path {socket} compat-system-probe"
        " >/tmp/dinit-system.log 2>&1 &"
    )

    with subtest("dinit supervises it as the user the description names"):
        machine.wait_until_succeeds(
            f"dinitctl --socket-path {socket} is-started compat-system-probe"
            " || { cat /tmp/dinit-system.log >&2; false; }",
            timeout=180,
        )
        pid = machine.succeed("pgrep -u compat-svc -f 'bin/sleep 3600'").strip()
        owner = machine.succeed(f"ps -o user= -p {pid}")
        assert owner.strip() == "compat-svc", f"the service runs as {owner.strip()}"

    with subtest("the environment the module generated reached the process"):
        env = machine.succeed(f"tr '\\0' '\\n' < /proc/{pid}/environ")
        assert "COMPAT_PROBE=set-by-dinit" in env, f"env-file was not applied: {env!r}"

    machine.shutdown()
  '';
}
