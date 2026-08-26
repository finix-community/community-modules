# nix-ld's whole job is that the path a foreign binary asks for - the
# platform's dynamic loader, /lib64/ld-linux-x86-64.so.2 on x86_64 - exists and
# resolves to nix-ld.
{
  machine = {
    services.mdevd.enable = true;

    programs.nix-ld.enable = true;
  };

  testScript =
    { nodes }:
    let
      pkgs = nodes.machine.config.nixpkgs.pkgs;

      inherit (pkgs.stdenv.hostPlatform) libDir;

      # the same name the module derives its tmpfiles rule from, so this test
      # follows the platform rather than hardcoding x86_64
      loader =
        "/${libDir}/"
        + builtins.unsafeDiscardStringContext (baseNameOf pkgs.stdenv.cc.bintools.dynamicLinker);
    in
    ''
      machine.start()
      machine.wait_for_console_text("entering runlevel 2", timeout=600)

      with subtest("tmpfiles created the loader symlink"):
          machine.wait_until_succeeds("test -L ${loader}", timeout=180)
          machine.succeed("test -x ${loader}")
          target = machine.succeed("readlink ${loader}")
          assert "nix-ld" in target, f"loader points at {target.strip()!r}, not nix-ld"

      with subtest("the libraries it hands out are installed"):
          machine.succeed("test -e /run/current-system/sw/share/nix-ld/lib/ld.so")

      with subtest("the library path is handed to logins by pam_env"):
          env = machine.succeed("cat /etc/security/pam_env.conf")
          assert "NIX_LD" in env, f"NIX_LD missing from the pam environment: {env!r}"

      machine.shutdown()
    '';
}
