# v2rayn is a gui client, but the module is not just `environment.systemPackages`:
# it wraps the binary so that the xray and sing-box cores are linked into the
# user's data directory on startup. that wrapper runs before the gui does, so it
# can be checked on a headless machine - and it is the part this repository owns.
{
  machine = {
    services.mdevd.enable = true;

    users.users.compat = {
      isNormalUser = true;
      home = "/home/compat";
      createHome = true;
    };

    programs.v2rayn.enable = true;
  };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2", timeout=600)

    with subtest("the client is installed"):
        machine.succeed("command -v v2rayN")

    # the gui will not come up without a display; the wrapper's setup runs
    # first either way, which is what is under test here
    machine.succeed("su compat -c 'v2rayN' >/home/compat/v2rayn.log 2>&1 &")

    cores = "/home/compat/.local/share/v2rayN/bin"

    with subtest("the wrapper linked the cores into the user's data directory"):
        machine.wait_until_succeeds(f"test -L {cores}/xray/xray", timeout=180)
        machine.wait_until_succeeds(f"test -L {cores}/sing_box/sing-box", timeout=180)

    with subtest("the links resolve to working binaries"):
        machine.succeed(f"{cores}/xray/xray version")
        machine.succeed(f"{cores}/sing_box/sing-box version")

    machine.shutdown()
  '';
}
