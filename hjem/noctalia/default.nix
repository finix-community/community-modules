{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) types;
  cfg = config.programs.noctalia;
  toml = pkgs.formats.toml { };
  json = pkgs.formats.json { };
  configToml =
    let
      rawConfig = toml.generate "config.toml" cfg.settings;
    in
    if cfg.validateConfig then
      pkgs.runCommand "noctalia-config" { } ''
        ${lib.getExe cfg.package} config validate ${rawConfig}
        cp ${rawConfig} $out
      ''
    else
      rawConfig;
  paletteFiles = lib.mapAttrs (
    name: palette: json.generate "${name}-palette.json" palette
  ) cfg.customPalettes;
in
{
  options.programs.noctalia = {
    enable = lib.mkEnableOption "Noctalia Wayland shell";

    package = lib.mkOption {
      type = types.package;
      default = pkgs.noctalia;
      description = "Noctalia package to install and run.";
    };

    validateConfig = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Validate the generated Noctalia configuration at build time.";
    };

    settings = lib.mkOption {
      type = toml.type;
      default = { };
      description = "Configuration written to $XDG_CONFIG_HOME/noctalia/config.toml.";
    };

    customPalettes = lib.mkOption {
      type = json.type;
      default = { };
      description = "Custom palettes written to $XDG_CONFIG_HOME/noctalia/palettes.";
    };
  };

  config = lib.mkIf cfg.enable {
    packages = [ cfg.package ];

    xdg.config.files = lib.mkMerge [
      (lib.mkIf (cfg.settings != { }) {
        "noctalia/config.toml".source = configToml;
      })
      (lib.mapAttrs' (
        name: source:
        lib.nameValuePair "noctalia/palettes/${name}.json" {
          inherit source;
        }
      ) paletteFiles)
    ];
  };
}
