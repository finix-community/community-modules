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

  getUserDirectories = lib.mapAttrsToList (_: userConfig: userConfig.directories);
  getUserFiles = lib.mapAttrsToList (_: userConfig: userConfig.files);

  getAllDirectories =
    stateConfig:
    stateConfig.directories ++ (builtins.concatLists (getUserDirectories stateConfig.users));

  getAllFiles =
    stateConfig: stateConfig.files ++ (builtins.concatLists (getUserFiles stateConfig.users));

  # produces shell commands for all bind mounts to run in the initrd after mount-all.
  # doing everything here means bind mounts persist through switch_root, so all paths are
  # available from the very start of stage 2.
  mkFinitInitrdMountCmds =
    _preserveAt: stateConfig:
    let
      allDirectories = getAllDirectories stateConfig;
      allFiles = getAllFiles stateConfig;
      bindmountDirs = builtins.filter (d: d.how == "bindmount") allDirectories;
      symlinkDirs = builtins.filter (d: d.how == "symlink") allDirectories;
      bindmountFiles = builtins.filter (f: f.how == "bindmount") allFiles;
      symlinkFiles = builtins.filter (f: f.how == "symlink") allFiles;

      prefix = "/sysroot";

      par = cmds: "( ${lib.concatStringsSep "; " cmds} ) &";

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
        par [
          "mkdir -p ${persistentPath}"
          "mount --mkdir --bind ${persistentPath} ${volatilePath}"
        ]
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
        par (
          lib.optionals dirConfig.createLinkTarget [ "mkdir -p ${persistentPath}" ]
          ++ [
            "mkdir -p ${parentDirectory volatilePath}"
            "ln -sf ${target} ${volatilePath}"
          ]
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
        par [
          "mkdir -p ${parentDirectory persistentPath}"
          "touch ${persistentPath}"
          "mkdir -p ${parentDirectory volatilePath}"
          "touch ${volatilePath}"
          "mount --bind ${persistentPath} ${volatilePath}"
        ]
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
        par (
          lib.optionals fileConfig.createLinkTarget [ "touch ${persistentPath}" ]
          ++ [
            "mkdir -p ${parentDirectory volatilePath}"
            "ln -sf ${target} ${volatilePath}"
          ]
        )
      ) symlinkFiles;
    in
    dirCmds ++ symlinkDirCmds ++ fileCmds ++ symlinkFileCmds ++ [ "wait" ];
}
