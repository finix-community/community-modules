# home-manager on finix is limited to what does not need a systemd user
# session: packages, files and program configuration. this asserts a managed
# file actually lands in the user's home after activation.
{
  machine = {
    services.mdevd.enable = true;

    users.users.compat = {
      isNormalUser = true;
      home = "/home/compat";
      createHome = true;
    };

    # the test vm bind-mounts the host store read-only, so home-manager's
    # `nix profile install` step cannot run.
    home-manager.enableProfileInstall = false;

    home-manager.users.compat = {
      home.username = "compat";
      home.homeDirectory = "/home/compat";
      home.stateVersion = "24.11";
      home.file.".compat-probe".text = "home-manager reached the home directory";
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2")

    with subtest("the managed file was linked into the home directory"):
        machine.wait_until_succeeds("test -e /home/compat/.compat-probe", timeout=180)
        content = machine.succeed("cat /home/compat/.compat-probe")
        assert "reached the home directory" in content, f"unexpected content: {content!r}"

    with subtest("it belongs to the user it was written for"):
        owner = machine.succeed("stat -Lc %U /home/compat/.compat-probe")
        assert owner.strip() == "compat", f"managed file owned by {owner.strip()}"

    machine.shutdown()
  '';
}
