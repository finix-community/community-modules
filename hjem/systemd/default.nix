{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  inherit (lib)
    attrsets
    lists
    modules
    options
    strings
    trivial
    types
    ;

  systemdUtils =
    (import (pkgs.path + "/nixos/lib/utils.nix") {
      inherit lib pkgs;
      config = lib.recursiveUpdate {
        systemd = {
          package = pkgs.systemd;
          globalEnvironment = { };
          enableStrictShellChecks = false;
        };
      } osConfig;
    }).systemdUtils;

  cfg = config.systemd;
  unitTypes = [
    "path"
    "service"
    "slice"
    "socket"
    "target"
    "timer"
  ];

  # Scan one unit directory from a package, returning a flat attrset of
  # relative path -> absolute store path for every regular file and symlink.
  # Subdirectories (e.g., drop-in *.d/, *.requires/, *.upholds/) are recursed one
  # level deep. .wants/ directories are intentionally skipped.
  # NixOS does the same, and handles them via a separate upstreamWants mechanism.
  scanUnitDir =
    dir:
    lib.optionalAttrs (builtins.pathExists dir) (
      let
        entries = attrsets.filterAttrs (_: t: t != "unknown") (builtins.readDir dir);
      in
      lib.foldl' (
        acc: name:
        let
          type = entries.${name};
          path = "${dir}/${name}";
        in
        if strings.hasSuffix ".wants" name then
          acc
        else if type == "regular" || type == "symlink" then
          acc // { ${name} = path; }
        else if type == "directory" then
          acc
          // attrsets.mapAttrs' (sub: _: attrsets.nameValuePair "${name}/${sub}" "${path}/${sub}") (
            attrsets.filterAttrs (_: t: t == "regular" || t == "symlink") (builtins.readDir path)
          )
        else
          acc
      ) { } (lib.attrNames entries)
    );

  # Collect all unit files exposed by a package, preferring lib/ over etc/
  # (same precedence as NixOS: etc/ is scanned first, then lib/ may overwrite).
  packageUnitFiles =
    pkg: scanUnitDir "${pkg}/etc/systemd/user" // scanUnitDir "${pkg}/lib/systemd/user";
in
{
  options.systemd =
    trivial.pipe unitTypes [
      (map (
        t:
        attrsets.nameValuePair "${t}s" (
          options.mkOption {
            default = { };
            type = systemdUtils.types."${t}s";
            description = "Definition of systemd per-user ${t} units.";
          }
        )
      ))
      builtins.listToAttrs
    ]
    // {
      enable = options.mkEnableOption "Hjem management of systemd units" // {
        default = true;
        example = false;
      };

      packages = options.mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = ''
          Packages containing systemd user unit files to be linked into
          {file}`~/.config/systemd/user/`. Unit files are taken from
          `$pkg/etc/systemd/user/` and `$pkg/lib/systemd/user/`.

          Units declared in {option}`systemd.services` and friends take
          precedence over package-provided units with the same name.
        '';
      };

      units = options.mkOption {
        type = systemdUtils.types.units;
        default = { };
        description = "Internal systemd user unit option to handle transformations.";
        internal = true;
      };
    };

  config = modules.mkIf cfg.enable {
    xdg.config.files =
      # Package-provided units come first so that user-declared units
      # (merged in with //) can override them.
      lib.foldl' (
        acc: pkg:
        acc
        // attrsets.mapAttrs' (
          name: path: attrsets.nameValuePair "systemd/user/${name}" { source = path; }
        ) (packageUnitFiles pkg)
      ) { } cfg.packages
      // builtins.listToAttrs (
        lists.flatten (
          attrsets.mapAttrsToList (
            name: unit:
            let
              src = "${systemdUtils.lib.makeUnit name unit}/${name}";
              mkEntry = path: attrsets.nameValuePair path { source = src; };
            in
            [ (mkEntry "systemd/user/${name}") ]
            ++ map (w: mkEntry "systemd/user/${w}.wants/${name}") (unit.wantedBy or [ ])
            ++ map (r: mkEntry "systemd/user/${r}.requires/${name}") (unit.requiredBy or [ ])
            ++ map (u: mkEntry "systemd/user/${u}.upholds/${name}") (unit.upheldBy or [ ])
            ++ map (a: attrsets.nameValuePair "systemd/user/${a}" { source = src; }) (unit.aliases or [ ])
          ) cfg.units
        )
      );

    systemd.units = trivial.pipe unitTypes [
      (map (
        t:
        attrsets.mapAttrsToList (
          n: v: attrsets.nameValuePair "${n}.${t}" (systemdUtils.lib."${t}ToUnit" v)
        ) cfg."${t}s"
      ))
      lists.flatten
      builtins.listToAttrs
    ];
  };
}
