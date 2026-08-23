{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.programs.fastfetch;

  fastfetch-unwrapped = pkgs.fastfetch-unwrapped.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./fastfetch.patch
    ];
  });
in
{
  options.programs.fastfetch = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable [fastfetch](${pkgs.fastfetch.meta.homepage}).
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.fastfetch.override {
        inherit fastfetch-unwrapped;
      };
      # defaultText = lib.literalExpression "pkgs.fastfetch";
      description = ''
        The package to use for `fastfetch`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
