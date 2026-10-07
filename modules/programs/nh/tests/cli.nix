# the always-on half of the module: the cli is installed, and when a flake is
# configured, NH_FLAKE reaches login shells the way the module documents.
{
  machine = {
    services.mdevd.enable = true;

    programs.nh.enable = true;
    programs.nh.flake = "/etc/nixos";
  };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2", timeout=600)

    with subtest("the cli is installed"):
        machine.succeed("nh --version")

    with subtest("NH_FLAKE reaches POSIX login shells"):
        out = machine.succeed("sh -lc 'echo $NH_FLAKE'")
        assert out.strip() == "/etc/nixos", f"unexpected NH_FLAKE: {out.strip()!r}"

    machine.shutdown()
  '';
}
