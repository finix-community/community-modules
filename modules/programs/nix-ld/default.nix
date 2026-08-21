{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.programs.nix-ld;

  libraries = pkgs.buildEnv {
    name = "nix-ld-libraries";
    pathsToLink = [ "/lib" ];
    paths = map lib.getLib cfg.libraries;
    postBuild = ''
      ln -s ${pkgs.stdenv.cc.bintools.dynamicLinker} $out/share/nix-ld/lib/ld.so
    '';
    extraPrefix = "/share/nix-ld";
    ignoreCollisions = true;
  };

  ldsoBasename = builtins.unsafeDiscardStringContext (
    lib.last (lib.splitString "/" pkgs.stdenv.cc.bintools.dynamicLinker)
  );
in
{
  options.programs.nix-ld = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable [nix-ld](https://github.com/nix-community/nix-ld). It installs a
        loader shim at the FHS location so unpatched dynamic executables can run without
        being repackaged for Nix
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nix-ld;
      defaultText = lib.literalExpression "pkgs.nix-ld";
      description = ''
        The package to use for `nix-ld`
      '';
    };

    libraries = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        Libraries made available under `NIX_LD_LIBRARY_PATH` to any unpatched dynamic
        executable run through `nix-ld`
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ libraries ];
    environment.pathsToLink = [ "/share/nix-ld" ];

    security.pam.environment = {
      NIX_LD.default = "/run/current-system/sw/share/nix-ld/lib/ld.so";
      NIX_LD_LIBRARY_PATH.default = "/run/current-system/sw/share/nix-ld/lib";
    };

    finit.tmpfiles.rules = [
      "d /${pkgs.stdenv.hostPlatform.libDir} 0755 root root - -"
      "L+ /${pkgs.stdenv.hostPlatform.libDir}/${ldsoBasename} - - - - ${cfg.package}/libexec/nix-ld"
    ];
  };
}
