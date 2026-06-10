{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.steam;

  extraCompatPaths = lib.makeSearchPathOutput "steamcompattool" "" cfg.extraCompatPackages;

in
{
  options.programs.steam = {
    enable = lib.mkEnableOption "steam";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.steam;
      defaultText = lib.literalExpression "pkgs.steam";
      example = lib.literalExpression ''
        pkgs.steam.override {
          extraEnv = {
            MANGOHUD = true;
            OBS_VKCAPTURE = true;
            RADV_TEX_ANISO = 16;
          };
          extraLibraries = p: with p; [
            atk
          ];
        }
      '';
      apply =
        steam:
        steam.override (prev: {
          extraEnv =
            (lib.optionalAttrs (cfg.extraCompatPackages != [ ]) {
              STEAM_EXTRA_COMPAT_TOOLS_PATHS = extraCompatPaths;
            })
            // (lib.optionalAttrs cfg.extest.enable {
              LD_PRELOAD = "${pkgs.pkgsi686Linux.extest}/lib/libextest.so";
            })
            // (prev.extraEnv or { });
          extraLibraries =
            pkgs:
            let
              prevLibs = if prev ? extraLibraries then prev.extraLibraries pkgs else [ ];
              additionalLibs =
                with config.hardware.graphics;
                if pkgs.stdenv.hostPlatform.is64bit then
                  [ package ] ++ extraPackages
                else
                  [ package32 ] ++ extraPackages32;
            in
            prevLibs ++ additionalLibs;
          extraPkgs = p: (cfg.extraPackages ++ lib.optionals (prev ? extraPkgs) (prev.extraPkgs p));
        });
      description = ''
        The Steam package to use. Additional libraries are added from the system
        configuration to ensure graphics work properly.

        Use this option to customise the Steam package rather than adding your
        custom Steam to {option}`environment.systemPackages` yourself.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression ''
        with pkgs; [
          gamescope
        ]
      '';
      description = ''
        Additional packages to add to the Steam environment.
      '';
    };

    extraCompatPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression ''
        with pkgs; [
          proton-ge-bin
        ]
      '';
      description = ''
        Extra packages to be used as compatibility tools for Steam on Linux. Packages will be included
        in the `STEAM_EXTRA_COMPAT_TOOLS_PATHS` environmental variable. For more information see
        https://github.com/ValveSoftware/steam-for-linux/issues/6310.

        These packages must be Steam compatibility tools that have a `steamcompattool` output.
      '';
    };

    fontPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      # `fonts.packages` is a list of paths now, filter out which are not packages
      default = builtins.filter lib.types.package.check config.fonts.packages;
      defaultText = lib.literalExpression "builtins.filter lib.types.package.check config.fonts.packages";
      example = lib.literalExpression "with pkgs; [ source-han-sans ]";
      description = ''
        Font packages to use in Steam.

        Defaults to system fonts, but could be overridden to use other fonts — useful for users who would like to customize CJK fonts used in Steam. According to the [upstream issue](https://github.com/ValveSoftware/steam-for-linux/issues/10422#issuecomment-1944396010), Steam only follows the per-user fontconfig configuration.
      '';
    };

    extest.enable = lib.mkEnableOption ''
      Load the extest library into Steam, to translate X11 input events to
      uinput events (e.g. for using Steam Input on Wayland)
    '';

    protontricks = {
      enable = lib.mkEnableOption "protontricks, a simple wrapper for running Winetricks commands for Proton-enabled games";
      package = lib.mkPackageOption pkgs "protontricks" { };
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.graphics = {
      # this fixes the "glXChooseVisual failed" bug, context: https://github.com/NixOS/nixpkgs/issues/47932
      enable = true;
      enable32Bit = true;
    };

    programs.steam.extraPackages = cfg.fontPackages;

    # enable 32bit pipewire support if needed
    programs.pipewire.alsa.support32Bit = config.programs.pipewire.alsa.enable;

    environment.systemPackages = [
      cfg.package
      cfg.package.run
    ]
    ++ lib.optional cfg.protontricks.enable (
      cfg.protontricks.package.override { inherit extraCompatPaths; }
    );

  };
}
