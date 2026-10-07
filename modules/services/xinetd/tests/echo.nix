# xinetd should accept a connection on a service port and hand it to the
# server program it was configured with.
{
  machine =
    { modules, pkgs, ... }:
    {
      imports = [ modules.sysklogd ];
      services.sysklogd.enable = true;
      services.xinetd.enable = true;
      services.xinetd.services = [
        {
          name = "compat-echo";
          unlisted = true;
          port = 7777;
          user = "nobody";
          # `cat` is the smallest possible echo server: xinetd hands it the
          # connected socket as stdin/stdout.
          server = "${pkgs.coreutils}/bin/cat";
        }
      ];
    };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2", timeout=600)

    with subtest("the daemon is running"):
        machine.wait_until_succeeds("pgrep -x xinetd", timeout=180)

    with subtest("the configured service answers"):
        machine.wait_for_open_port(7777, timeout=180)
        reply = machine.succeed("echo compat-probe | nc -N 127.0.0.1 7777")
        assert reply.strip() == "compat-probe", f"echo service returned {reply.strip()!r}"

    machine.shutdown()
  '';
}
