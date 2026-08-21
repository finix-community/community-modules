let
  programModules = builtins.mapAttrs (dir: _: ./programs/${dir}) (
    builtins.removeAttrs (builtins.readDir ./programs) [
      "README.md"
    ]
  );

  serviceModules = builtins.mapAttrs (dir: _: ./services/${dir}) (
    builtins.removeAttrs (builtins.readDir ./services) [
      "README.md"
    ]
  );
  profileModules = builtins.mapAttrs (dir: _: ./profiles/${dir}) (
    builtins.removeAttrs (builtins.readDir ./profiles) [
      "README.md"
    ]
  );
in
programModules // serviceModules // profileModules // { dinit = ./dinit; }
