{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.preservation;

  inherit (import ./lib.nix { inherit lib; })
    mkFinitInitrdMountCmds
    getReferencedUsers
    getReferencedGroups
    ;

  # ownership is applied from the initrd, where no passwd/group database exists
  # beyond root, so names have to be resolved to numeric ids at evaluation time.
  # a null id means finix lets userborn pick one during stage 2 activation,
  # which is too late for us - see the assertions below.
  lookupUid = name: config.users.users.${name}.uid or null;
  lookupGid = name: config.users.groups.${name}.gid or null;

  ids = {
    uid = name: toString (lookupUid name);
    gid = name: toString (lookupGid name);
  };

  allCmds = lib.flatten (lib.mapAttrsToList (mkFinitInitrdMountCmds ids) cfg.preserveAt);
  script = pkgs.writeScript "preservation-initrd" ''
    #!/bin/sh
    ${lib.concatStringsSep "\n" allCmds}
  '';

  # finix's initrd mounts every neededForBoot filesystem in a single
  # `mount-all` task; there are no per-root mount tasks.
  mountConditions = "task/mount-all/success";

  referencedUsers = lib.unique (lib.concatMap getReferencedUsers (lib.attrValues cfg.preserveAt));
  referencedGroups = lib.unique (lib.concatMap getReferencedGroups (lib.attrValues cfg.preserveAt));
in
{
  imports = [
    ./options.nix
  ];

  config = lib.mkIf (cfg.enable && allCmds != [ ]) {
    assertions =
      map (name: {
        assertion = lookupUid name != null;
        message = ''
          preservation: user "${name}" owns preserved state but has no statically
          assigned uid. Ownership is applied in the initrd, before dynamic ids are
          allocated, so set `users.users.${name}.uid`.
        '';
      }) referencedUsers
      ++ map (name: {
        assertion = lookupGid name != null;
        message = ''
          preservation: group "${name}" owns preserved state but has no statically
          assigned gid. Ownership is applied in the initrd, before dynamic ids are
          allocated, so set `users.groups.${name}.gid`.
        '';
      }) referencedGroups;

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
