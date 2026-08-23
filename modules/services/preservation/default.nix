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
    getAllDirectories
    getAllFiles
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

  # finix gives every neededForBoot filesystem its own initrd mount task, named
  # after the mountpoint it mounts. these two mirror `escapePath` and the
  # prefix test in finix's `modules/lib/utils.nix` and `modules/finit/mount.nix`
  # respectively; they are duplicated rather than imported because this module
  # is evaluated as a plain nixos module and has no access to finix's `utils`.
  escapePath = s: if s == "/" then "root" else lib.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "/" s);

  # "/nix" precedes "/nix/store" but not "/nixos"; "/" precedes everything
  pathIsPrefix = a: b: a == b || a == "/" || lib.hasPrefix (a + "/") b;

  bootFilesystems = lib.filter (fs: fs.neededForBoot) (lib.attrValues config.fileSystems);

  # the mountpoint a path resolves through, i.e. the deepest mountpoint that
  # prefixes it. `persistentStoragePath` is not required to be a mountpoint
  # itself - it is allowed to sit inside one - so this cannot just escape the
  # path directly.
  mountPointFor =
    path:
    let
      candidates = lib.filter (fs: pathIsPrefix fs.mountPoint path) bootFilesystems;
      deepestFirst = lib.sort (
        a: b: builtins.stringLength a.mountPoint > builtins.stringLength b.mountPoint
      ) candidates;
    in
    if candidates == [ ] then null else (lib.head deepestFirst).mountPoint;

  # an entry may only be set up once every volume it touches is mounted: the one
  # backing the persistent copies, and the ones its mountpoints live on.
  conditionsFor =
    stateConfig:
    let
      paths =
        [ stateConfig.persistentStoragePath ]
        ++ map (d: d.directory) (getAllDirectories stateConfig)
        ++ map (f: f.file) (getAllFiles stateConfig);
      mountPoints = lib.unique (lib.filter (m: m != null) (map mountPointFor paths));
    in
    lib.concatMapStringsSep "," (m: "task/mount-${escapePath m}/success") (
      lib.sort (a: b: a < b) mountPoints
    );

  # one unit per `preserveAt` entry, so each volume is set up as soon as it is
  # available instead of every entry waiting on the slowest one.
  entries = lib.filter (e: e.cmds != [ ]) (
    lib.mapAttrsToList (name: stateConfig: {
      inherit stateConfig;
      unit = "preservation-${escapePath stateConfig.persistentStoragePath}";
      cmds = mkFinitInitrdMountCmds ids name stateConfig;
    }) cfg.preserveAt
  );

  # a preserved path that cannot be set up is a bad reason to refuse to boot, so
  # every entry is guarded (see `guard` in lib.nix) and this script always exits
  # 0. the cost is that failures are only ever reported, never enforced - hence
  # writing to the console directly, so the warning is visible even though finit
  # is told the task succeeded.
  mkScript =
    entry:
    pkgs.writeScript "${entry.unit}-initrd" ''
      #!/bin/sh
      preservation_warn() {
        msg="preservation: failed to set up $1, continuing without it"
        echo "$msg" >&2
        if [ -w /dev/console ]; then echo "$msg" > /dev/console; fi
        return 0
      }

      ${lib.concatStringsSep "\n" entry.cmds}

      exit 0
    '';

  referencedUsers = lib.unique (lib.concatMap getReferencedUsers (lib.attrValues cfg.preserveAt));
  referencedGroups = lib.unique (lib.concatMap getReferencedGroups (lib.attrValues cfg.preserveAt));
in
{
  imports = [
    ./options.nix
  ];

  config = lib.mkIf (cfg.enable && entries != [ ]) {
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
      }) referencedGroups
      ++ map (entry: {
        assertion = conditionsFor entry.stateConfig != "";
        message = ''
          preservation: no `neededForBoot` filesystem provides
          "${entry.stateConfig.persistentStoragePath}". The preserved paths are set
          up from the initrd, so the volume holding them has to be mounted there -
          set `fileSystems."<mountpoint>".neededForBoot = true`.
        '';
      }) entries;

    boot.initrd.contents = lib.concatMap (entry: [
      {
        target = "/usr/local/bin/${entry.unit}";
        source = mkScript entry;
      }
      {
        target = "/etc/finit.d/${entry.unit}.conf";
        source = pkgs.writeText "${entry.unit}-finit-initrd.conf" ''
          run [S] name:${entry.unit} <${conditionsFor entry.stateConfig}> ${entry.unit}
        '';
      }
    ]) entries;
  };
}
