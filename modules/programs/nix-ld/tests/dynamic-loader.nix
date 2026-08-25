# nix-ld's whole job is that the path a foreign binary asks for -
# /lib64/ld-linux-x86-64.so.2 and friends - exists and resolves.
{
  machine = {
    services.mdevd.enable = true;

    programs.nix-ld.enable = true;
  };

  testScript =
    { nodes }:
    let
      inherit (nodes.machine.config.nixpkgs.pkgs.stdenv.hostPlatform) libDir;
    in
    ''
      machine.start()
      machine.wait_for_console_text("entering runlevel 2", timeout=600)

      with subtest("tmpfiles created the loader symlink"):
          machine.wait_until_succeeds("test -L /${libDir}/ld-linux-x86-64.so.2", timeout=180)
          machine.succeed("test -x /${libDir}/ld-linux-x86-64.so.2")
          target = machine.succeed("readlink /${libDir}/ld-linux-x86-64.so.2")
          assert "nix-ld" in target, f"loader points at {target.strip()!r}, not nix-ld"

      with subtest("the libraries it hands out are installed"):
          machine.succeed("test -e /run/current-system/sw/share/nix-ld/lib/ld.so")

      with subtest("the library path is handed to logins by pam_env"):
          env = machine.succeed("cat /etc/security/pam_env.conf")
          assert "NIX_LD" in env, f"NIX_LD missing from the pam environment: {env!r}"

      machine.shutdown()
    '';
}
