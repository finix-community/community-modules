{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.dinit;
in
{
  options.dinit = {
    directory = lib.mkOption {
      type = lib.types.str;
      default = ".config/dinit.d";
    };

    services = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          imports = [ ./options.nix ];
        }
      );
      default = { };
      description = ''
        An attribute set of `dinit` user level services.

        See [upstream documentation](https://davmac.org/projects/dinit/man-pages-html/dinit-service.5.html) for additional details.
      '';
    };
  };

  config = {
    files =
      let
        settingsFormat = import ./format.nix { inherit pkgs lib; };
        extraAttrs = [
          "enable"
          "environment"
          "path"
        ];

        serviceTree = lib.mapAttrs' (name: service: {
          name = "${cfg.directory}/${name}";
          value.source = settingsFormat.generate name (builtins.removeAttrs service extraAttrs);
        }) cfg.services;

        enabledTree = lib.mapAttrs' (name: service: {
          name = "${cfg.directory}/boot.d/${name}";
          # value.source = "${config.directory}/${cfg.directory}/${name}";
          value.source = settingsFormat.generate name (builtins.removeAttrs service extraAttrs);
        }) (lib.filterAttrs (_: service: service.enable) cfg.services);
      in
      serviceTree // enabledTree;
  };
}
