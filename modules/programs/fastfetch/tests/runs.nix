# fastfetch reads a lot of the running system to produce its output; running it
# is a cheap way to notice when finix stops laying down something it expects.
{
  machine = {
    services.mdevd.enable = true;

    programs.fastfetch.enable = true;
  };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2")

    with subtest("it is on PATH"):
        machine.succeed("fastfetch --version")

    with subtest("it can describe the running system"):
        out = machine.succeed("fastfetch --pipe --structure OS:Kernel:Shell")
        assert "Kernel" in out, f"unexpected output: {out!r}"

    machine.shutdown()
  '';
}
