# home-manager on finix is limited to what does not need a systemd user
# session: packages, files and program configuration. this asserts a managed
# file actually lands in the user's home after activation.
#
# activation itself is not run here, and cannot be: it sets the generation
# profile with `nix-env`, and the test vm's /nix is a read-only 9p mount of the
# host store, so nix fails before it starts. what is checked instead is
# everything up to that point - the service the module wires into the boot
# sequence, and the generation it points at, including the managed file
# home-manager built into it. a writable store would need an overlay the test
# driver does not set up.
{
  machine = {
    services.mdevd.enable = true;

    # activation shells out to nix, which wants a writable /tmp. the driver's
    # root is a fresh tmpfs where /tmp ends up mode 755, and laying it down as
    # its own tmpfs gets the sticky mode in place before anything runs
    fileSystems."/tmp" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "mode=1777" ];
    };

    users.users.compat = {
      isNormalUser = true;
      home = "/home/compat";
      createHome = true;
    };

    # the store is read-only here, so home-manager's `nix profile install` step
    # could not run even if it were reached
    home-manager.enableProfileInstall = false;

    home-manager.users.compat = {
      home.username = "compat";
      home.homeDirectory = "/home/compat";
      home.stateVersion = "24.11";
      home.file.".compat-probe".text = "home-manager reached the home directory";
    };
  };

  testScript =
    { nodes }:
    let
      generation = nodes.machine.config.home-manager.users.compat.home.activationPackage;
    in
    ''
      machine.start()
      machine.wait_for_console_text("entering runlevel 2", timeout=600)

      with subtest("the module wired activation into the boot sequence"):
          machine.succeed("test -e /etc/finit.d/hm-activate-compat.conf")
          unit = machine.succeed("cat /etc/finit.d/hm-activate-compat.conf")
          assert "${generation}" in unit, unit

      with subtest("the generation carries the managed file activation would link"):
          machine.succeed("test -e ${generation}/home-files/.compat-probe")
          content = machine.succeed("cat ${generation}/home-files/.compat-probe")
          assert "reached the home directory" in content, f"unexpected content: {content!r}"

      with subtest("the generation is a runnable activation package"):
          machine.succeed("test -x ${generation}/activate")

      with subtest("the user it was built for exists with that home"):
          home = machine.succeed("getent passwd compat | cut -d: -f6")
          assert home.strip() == "/home/compat", f"home is {home.strip()!r}"
          machine.succeed("test -d /home/compat")

      machine.shutdown()
    '';
}
