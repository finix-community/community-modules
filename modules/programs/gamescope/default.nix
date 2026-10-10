{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.gamescope;

  udevApi =
    if config.services.gardendevd.enable then
      pkgs.libudev-garden
    else if config.services.mdevd.enable || config.services.keventd.enable then
      pkgs.libudev-zero
    else
      null;

  libinput = pkgs.libinput.override (
    lib.optionalAttrs (udevApi != null) {
      udev = udevApi;
      wacomSupport = false;
    }
  );

  gamescope =
    let
      wrapperArgs =
        lib.optional (cfg.args != [ ]) ''--add-flags "${toString cfg.args}"''
        ++ builtins.attrValues (builtins.mapAttrs (var: val: "--set-default ${var} ${val}") cfg.env);
    in
    pkgs.runCommand "gamescope" { nativeBuildInputs = [ pkgs.makeBinaryWrapper ]; } ''
      mkdir -p $out/bin
      makeWrapper ${cfg.package}/bin/gamescope $out/bin/gamescope --inherit-argv0 \
        ${toString wrapperArgs}
      ln -s ${cfg.package}/bin/gamescopectl $out/bin/gamescopectl
    '';
in
{
  options.programs.gamescope = {
    enable = lib.mkEnableOption "gamescope, the SteamOS session compositing window manager";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.gamescope.override (
        o:
        let
          wlrootsAttr = lib.head (lib.filter (lib.hasPrefix "wlroots") (lib.attrNames o));
        in
        {
          inherit libinput;
          ${wlrootsAttr} = o.${wlrootsAttr}.override { inherit libinput; };
        }
      );
      defaultText = lib.literalExpression "pkgs.gamescope";
      description = "The Gamescope package to use.";
    };

    capSysNice = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Add cap_sys_nice capability to the GameScope
        binary so that it may renice itself.
      '';
    };

    args = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "--rt"
        "--prefer-vk-device 8086:9bc4"
      ];
      description = ''
        Arguments passed to GameScope on startup.
      '';
    };

    env = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = lib.literalExpression ''
        # for Prime render offload on Nvidia laptops.
        # Also requires `hardware.nvidia.prime.offload.enable`.
        {
          __NV_PRIME_RENDER_OFFLOAD = "1";
          __VK_LAYER_NV_optimus = "NVIDIA_only";
          __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        }
      '';
      description = ''
        Default environment variables available to the GameScope process, overridable at runtime.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    security.wrappers = lib.mkIf cfg.capSysNice {
      gamescope = {
        owner = "root";
        group = "root";
        source = "${gamescope}/bin/gamescope";
        capabilities = "cap_sys_nice+pie";
      };
    };

    environment.systemPackages = lib.mkIf (!cfg.capSysNice) [ gamescope ];
  };

  meta.maintainers = [ ];
}
