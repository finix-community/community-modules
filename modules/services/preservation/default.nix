{
  config,
  pkgs,
  lib,
  utils,
  ...
}:
let
  cfg = config.preservation;

  inherit (import ./lib.nix { inherit lib; })
    mkFinitInitrdMountCmds
    ;

  inherit (utils) escapePath;

  allCmds = lib.flatten (lib.mapAttrsToList mkFinitInitrdMountCmds cfg.preserveAt);
  script = pkgs.writeScript "preservation-initrd" ''
    #!/bin/sh
    ${lib.concatStringsSep "\n" allCmds}
  '';

  mountConditions = lib.concatMapStringsSep "," (root: "task/mount-${escapePath root}/success") (
    lib.attrNames cfg.preserveAt
  );
in
{
  imports = [
    ./options.nix
  ];

  config = lib.mkIf (cfg.enable && allCmds != [ ]) {
    boot.initrd.contents = [
      {
        target = "/usr/local/bin/preservation";
        source = script;
      }
      {
        target = "/etc/finit.d/preservation.conf";
        source = pkgs.writeText "preservation-finit-initrd.conf" ''
          run [S] name:preservation <${mountConditions}> preservation
        '';
      }
    ];
  };
}
