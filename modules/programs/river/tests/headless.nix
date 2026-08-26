# wlroots has a headless backend, so river can be run without a gpu or a seat.
# that exercises the part of the module that tends to break: it rebuilds river
# against the udev api the configured device manager provides - libudev-zero
# under mdevd - and generates the init script the session runs.
{
  machine = {
    services.mdevd.enable = true;

    # xwayland wants to create its socket under /tmp/.X11-unix, and the
    # driver's root is a fresh tmpfs where /tmp ends up mode 755
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

    programs.river.enable = true;
    programs.river.init = ''
      riverctl map normal Super Return spawn foot
      riverctl default-layout rivertile
      touch "$HOME/river-init-ran"
    '';
  };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2", timeout=600)

    with subtest("the session file and init script were installed"):
        machine.succeed("test -e /run/current-system/sw/share/wayland-sessions/river.desktop")
        machine.succeed("command -v river-init")

    machine.succeed("mkdir -p /run/user/1000 && chown compat: /run/user/1000")
    env = "XDG_RUNTIME_DIR=/run/user/1000 WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1"
    as_user = lambda cmd: f"su compat -c {(env + ' ' + cmd)!r}"

    machine.succeed(as_user("river -c river-init") + " >/tmp/river.log 2>&1 &")

    with subtest("the compositor comes up"):
        machine.wait_until_succeeds(
            "test -S /run/user/1000/wayland-0 || test -S /run/user/1000/wayland-1"
            " || { cat /tmp/river.log >&2; false; }",
            timeout=180,
        )
        machine.wait_until_succeeds("pgrep -u compat -x river", timeout=180)

    with subtest("it ran the init script the module generated"):
        machine.wait_until_succeeds("test -e /home/compat/river-init-ran", timeout=180)

    # river 0.4 split riverctl and rivertile out of the river repository, and
    # this nixpkgs packages neither - so the init script the module generates,
    # whose whole documented purpose is riverctl calls, has nothing to run
    with subtest("the init script's riverctl commands are runnable"):
        display = machine.succeed(
            "ls /run/user/1000 | grep -m1 '^wayland-[0-9]$'"
        ).strip()
        machine.succeed(as_user(f"WAYLAND_DISPLAY={display} riverctl default-layout rivertile"))

    machine.shutdown()
  '';
}
