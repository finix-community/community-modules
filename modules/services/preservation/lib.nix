{ lib, ... }:
rec {
  # concatenates two paths
  # inserts a "/" in between if there is none, removes one if there are two
  concatTwoPaths =
    parent: child:
    with lib.strings;
    if hasSuffix "/" parent then
      if
        hasPrefix "/" child
      # "/parent/" "/child"
      then
        parent + (removePrefix "/" child)
      # "/parent/" "child"
      else
        parent + child
    else if
      hasPrefix "/" child
    # "/parent" "/child"
    then
      parent + child
    # "/parent" "child"
    else
      parent + "/" + child;

  # concatenates a list of paths using `concatTwoPaths`
  concatPaths = builtins.foldl' concatTwoPaths "";

  # get the parent directory of an absolute path
  parentDirectory =
    path:
    with lib.strings;
    assert "/" == (builtins.substring 0 1 path);
    let
      parts = splitString "/" (removeSuffix "/" path);
      len = builtins.length parts;
    in
    if len < 1 then "/" else concatPaths ([ "/" ] ++ (lib.lists.sublist 0 (len - 1) parts));

  # splits a path on "/", returning a list of non-empty path components
  parts =
    path:
    builtins.foldl' (acc: p: if builtins.isString p && p != "" then acc ++ [ p ] else acc) [ ] (
      builtins.split "/" path
    );

  # generates a list of path segments that are parents of the given path
  # e.g.: for "/foo/bar/baz" this yields [ "foo/bar" "foo" ]
  parentSegments =
    path:
    let
      # collect all path segments, including the given path itself
      includingPath = builtins.foldl' (
        acc: part: if acc == [ ] then [ part ] else ([ (concatTwoPaths (builtins.head acc) part) ] ++ acc)
      ) [ ] (parts path);
      # return all path segments except for the given path
    in
    builtins.tail includingPath;

  # generates a list of unique path segments that are parents of a given list of
  # paths, excluding those that are already part of that list
  missingIntermediatePaths =
    paths:
    let
      intermediates = builtins.foldl' (acc: path: acc ++ (parentSegments path)) [ ] paths;
    in
    lib.lists.unique (builtins.filter (path: !(builtins.elem path paths)) intermediates);

  # generates a list of attributes to be used in the `directories` option of the `userModule`
  #
  # essentially this takes the given lists of configurations for `directories` and `files`,
  # generates a list of all their unique parent paths and returns a single list of the
  # given configurations extended by the configurations for their parents, using `defaults`.
  #
  # without this, preserving e.g. `.config/someapp/state` would leave `.config` owned by
  # root, so the user could no longer create anything else in it.
  mkIntermediateUserDirectories =
    defaults: files: prefix: directories:
    let
      # `files` have already had the home prefix applied, `directories` have not
      toPaths = map (
        d: if builtins.hasAttr "file" d then lib.removePrefix prefix d.file else d.directory
      );
      intermediates = map (p: defaults // { directory = p; }) (
        missingIntermediatePaths (toPaths (files ++ directories))
      );
    in
    directories ++ intermediates;

  getUserDirectories = lib.mapAttrsToList (_: userConfig: userConfig.directories);
  getUserFiles = lib.mapAttrsToList (_: userConfig: userConfig.files);

  getAllDirectories =
    stateConfig:
    stateConfig.directories ++ (builtins.concatLists (getUserDirectories stateConfig.users));

  getAllFiles =
    stateConfig: stateConfig.files ++ (builtins.concatLists (getUserFiles stateConfig.users));

  # users whose home directory is materialized on the persistent volume
  getActiveUsers = lib.filterAttrs (_: u: u.directories != [ ] || u.files != [ ]);

  # every user name whose id has to be resolved to preserve this prefix.
  # ownership is applied in the initrd, so `default.nix` asserts that all of
  # these have a statically assigned uid.
  getReferencedUsers =
    stateConfig:
    let
      entries = (getAllDirectories stateConfig) ++ (getAllFiles stateConfig);
    in
    lib.unique (
      (map (e: e.user) entries)
      ++ (map (e: e.parent.user) (builtins.filter (e: e.configureParent) entries))
      ++ (lib.mapAttrsToList (_: u: u.username) (getActiveUsers stateConfig.users))
    );

  # the group counterpart of `getReferencedUsers`
  getReferencedGroups =
    stateConfig:
    let
      entries = (getAllDirectories stateConfig) ++ (getAllFiles stateConfig);
    in
    lib.unique (
      (map (e: e.group) entries)
      ++ (map (e: e.parent.group) (builtins.filter (e: e.configureParent) entries))
      ++ (lib.mapAttrsToList (_: u: u.homeGroup) (getActiveUsers stateConfig.users))
    );

  # renders a list of `{ name, value }` mount options as a `mount -o` argument
  renderMountOptions = lib.concatMapStringsSep "," (
    o: if o.value == null then o.name else "${o.name}=${o.value}"
  );

  # produces shell commands for all bind mounts to run in the initrd after mount-all.
  # doing everything here means bind mounts persist through switch_root, so all paths are
  # available from the very start of stage 2.
  #
  # `ids` resolves user/group names to the numeric ids used by `chown`. names are
  # deliberately not used: the initrd has no passwd/group database for anything
  # but root, and dynamically allocated ids do not exist yet at this point.
  mkFinitInitrdMountCmds =
    ids: _preserveAt: stateConfig:
    let
      allDirectories = getAllDirectories stateConfig;
      allFiles = getAllFiles stateConfig;
      bindmountDirs = builtins.filter (d: d.how == "bindmount") allDirectories;
      symlinkDirs = builtins.filter (d: d.how == "symlink") allDirectories;
      # not preserved themselves, they only need to exist with the right ownership
      intermediateDirs = builtins.filter (d: d.how == "_intermediate") allDirectories;
      bindmountFiles = builtins.filter (f: f.how == "bindmount") allFiles;
      symlinkFiles = builtins.filter (f: f.how == "symlink") allFiles;

      prefix = "/sysroot";

      # runs the commands for one entry as a group.
      #
      # the commands are chained with `&&` so the group stops at the first
      # failure, and a path that could not be prepared is never mounted over
      # half-done - when the persistent copy turns out to be the wrong type, the
      # volatile mountpoint is left absent rather than present and empty, which
      # would silently swallow everything written to it.
      #
      # `set -e` deliberately is not used here: POSIX suspends errexit for any
      # command that is the left operand of `||`, and both bash and ash extend
      # that suspension to a `set -e` executed inside the compound command. the
      # group below is exactly such an operand, so errexit would be a no-op.
      #
      # `|| preservation_warn` then contains the failure. preserving state is not
      # worth refusing to boot over, so a broken entry degrades to a warning on
      # the console while every other entry is still set up. the warn helper is
      # defined in the script preamble in `default.nix`.
      guard =
        {
          background ? true,
        }:
        label: cmds:
        "( ${lib.concatStringsSep " && " cmds} ) || preservation_warn ${lib.escapeShellArg label}"
        + lib.optionalString background " &";

      par = guard { };
      serial = guard { background = false; };

      # apply ownership and permissions to a path this script has just created
      mkOwn =
        {
          user,
          group,
          mode,
          ...
        }:
        path: [
          "chown ${ids.uid user}:${ids.gid group} ${path}"
          "chmod ${mode} ${path}"
        ];

      # missing parent directories are created as root:root 0755 by default;
      # `configureParent` gives them the ownership and mode declared on the entry.
      # applied to both the volatile and the persistent copy of the parent.
      mkParent =
        entry: paths:
        lib.optionals entry.configureParent (
          lib.concatMap (
            path:
            let
              parent = parentDirectory path;
            in
            [ "mkdir -p ${parent}" ] ++ mkOwn { inherit (entry.parent) user group mode; } parent
          ) paths
        );

      # home directories are created up front, sequentially, so that the parallel
      # per-entry commands below never race to create them.
      homeCmds = lib.mapAttrsToList (
        _: userConfig:
        let
          persistentHome = concatPaths [
            prefix
            stateConfig.persistentStoragePath
            userConfig.home
          ];
        in
        serial userConfig.home (
          [ "mkdir -p ${persistentHome}" ]
          ++ mkOwn {
            user = userConfig.username;
            group = userConfig.homeGroup;
            mode = userConfig.homeMode;
          } persistentHome
        )
      ) (getActiveUsers stateConfig.users);

      # like `homeCmds`, emitted sequentially and shallowest first, so that the
      # parallel per-entry commands below can only ever find them already in place.
      intermediateCmds =
        map
          (
            dirConfig:
            let
              persistentPath = concatPaths [
                prefix
                stateConfig.persistentStoragePath
                dirConfig.directory
              ];
              volatilePath = concatPaths [
                prefix
                dirConfig.directory
              ];
            in
            serial dirConfig.directory (
              [ "mkdir -p ${persistentPath}" ]
              ++ mkOwn dirConfig persistentPath
              ++ [ "mkdir -p ${volatilePath}" ]
              ++ mkOwn dirConfig volatilePath
            )
          )
          (
            lib.sort (
              a: b: builtins.lessThan (builtins.stringLength a.directory) (builtins.stringLength b.directory)
            ) intermediateDirs
          );

      dirCmds = map (
        dirConfig:
        let
          persistentPath = concatPaths [
            prefix
            stateConfig.persistentStoragePath
            dirConfig.directory
          ];
          volatilePath = concatPaths [
            prefix
            dirConfig.directory
          ];
        in
        par dirConfig.directory (
          [
            "mkdir -p ${persistentPath}"
            "mkdir -p ${volatilePath}"
          ]
          ++ mkOwn dirConfig persistentPath
          ++ mkParent dirConfig [
            persistentPath
            volatilePath
          ]
          ++ [
            "mount -o ${renderMountOptions dirConfig.mountOptions} ${persistentPath} ${volatilePath}"
          ]
        )
      ) bindmountDirs;

      symlinkDirCmds = map (
        dirConfig:
        let
          persistentPath = concatPaths [
            prefix
            stateConfig.persistentStoragePath
            dirConfig.directory
          ];
          volatilePath = concatPaths [
            prefix
            dirConfig.directory
          ];
          target = concatPaths [
            stateConfig.persistentStoragePath
            dirConfig.directory
          ];
        in
        par dirConfig.directory (
          lib.optionals dirConfig.createLinkTarget (
            [ "mkdir -p ${persistentPath}" ] ++ mkOwn dirConfig persistentPath
          )
          ++ [ "mkdir -p ${parentDirectory volatilePath}" ]
          ++ mkParent dirConfig [
            persistentPath
            volatilePath
          ]
          ++ [ "ln -sf ${target} ${volatilePath}" ]
        )
      ) symlinkDirs;

      fileCmds = map (
        fileConfig:
        let
          persistentPath = concatPaths [
            prefix
            stateConfig.persistentStoragePath
            fileConfig.file
          ];
          volatilePath = concatPaths [
            prefix
            fileConfig.file
          ];
        in
        par fileConfig.file (
          [
            "mkdir -p ${parentDirectory persistentPath}"
            "touch ${persistentPath}"
            "mkdir -p ${parentDirectory volatilePath}"
            "touch ${volatilePath}"
          ]
          ++ mkOwn fileConfig persistentPath
          ++ mkParent fileConfig [
            persistentPath
            volatilePath
          ]
          ++ [
            "mount -o ${renderMountOptions fileConfig.mountOptions} ${persistentPath} ${volatilePath}"
          ]
        )
      ) bindmountFiles;

      symlinkFileCmds = map (
        fileConfig:
        let
          persistentPath = concatPaths [
            prefix
            stateConfig.persistentStoragePath
            fileConfig.file
          ];
          volatilePath = concatPaths [
            prefix
            fileConfig.file
          ];
          target = concatPaths [
            stateConfig.persistentStoragePath
            fileConfig.file
          ];
        in
        par fileConfig.file (
          lib.optionals fileConfig.createLinkTarget (
            [
              "mkdir -p ${parentDirectory persistentPath}"
              "touch ${persistentPath}"
            ]
            ++ mkOwn fileConfig persistentPath
          )
          ++ [ "mkdir -p ${parentDirectory volatilePath}" ]
          ++ mkParent fileConfig [
            persistentPath
            volatilePath
          ]
          ++ [ "ln -sf ${target} ${volatilePath}" ]
        )
      ) symlinkFiles;
    in
    homeCmds
    ++ intermediateCmds
    ++ dirCmds
    ++ symlinkDirCmds
    ++ fileCmds
    ++ symlinkFileCmds
    ++ [ "wait" ];
}
