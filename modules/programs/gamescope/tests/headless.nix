# gamescope has a headless backend, so it can be started and asked to run a
# child on a machine with no gpu and no seat. that covers what the module does:
# put a working gamescope on the system, with or without the cap_sys_nice
# wrapper.
{
  machine =
    { pkgs, ... }:
    {
      services.mdevd.enable = true;

      # gamescope wants vulkan even headless; lavapipe is mesa's software
      # renderer, which is the only one a vm is getting
      hardware.graphics.enable = true;
      hardware.graphics.extraPackages = [ pkgs.mesa ];

      programs.gamescope.enable = true;
    };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2", timeout=600)

    with subtest("the compositor and its control tool are installed"):
        machine.succeed("command -v gamescope")
        machine.succeed("command -v gamescopectl")
        # no pipe: the shell runs with pipefail and gamescope dies of SIGPIPE
        machine.succeed("gamescope --help >/tmp/gamescope-help 2>&1 || true")
        assert "gamescope version" in machine.succeed("cat /tmp/gamescope-help")

    with subtest("it starts headless and runs its child"):
        machine.succeed("mkdir -p /run/user/0")
        machine.succeed(
            "XDG_RUNTIME_DIR=/run/user/0"
            " VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/lvp_icd.x86_64.json"
            " gamescope --backend headless"
            " -- /bin/sh -c 'echo ran > /tmp/gamescope-child'"
            " >/tmp/gamescope.log 2>&1 &"
        )
        machine.wait_until_succeeds(
            "test -f /tmp/gamescope-child || { cat /tmp/gamescope.log >&2; false; }",
            timeout=180,
        )

    machine.shutdown()
  '';
}
