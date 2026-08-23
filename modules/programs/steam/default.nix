{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.steam;

  extraCompatPaths = lib.makeSearchPathOutput "steamcompattool" "" cfg.extraCompatPackages;

  steam-gamescope =
    let
      exports = builtins.attrValues (
        builtins.mapAttrs (n: v: "export ${n}=${v}") cfg.gamescopeSession.env
      );
    in
    pkgs.writeShellScriptBin "steam-gamescope" ''
      ${builtins.concatStringsSep "\n" exports}
      gamescope --steam ${toString cfg.gamescopeSession.args} -- steam ${toString cfg.gamescopeSession.steamArgs}
    '';

  gamescopeSessionFile =
    (pkgs.writeTextDir "share/wayland-sessions/steam.desktop" ''
      [Desktop Entry]
      Name=Steam
      Comment=A digital distribution platform
      Exec="${pkgs.dbus}/bin/dbus-run-session -- ${steam-gamescope}/bin/steam-gamescope"
      Type=Application
    '').overrideAttrs
      (_: {
        passthru.providedSessions = [ "steam" ];
      });

in
{
  # FIXME we do not like relative paths...
  imports = [ ../gamescope ];

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

    # TODO implement firewall options once #121 is merged
    # https://github.com/finix-community/finix/pull/121

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

    gamescopeSession = lib.mkOption {
      description = "Run a GameScope driven Steam session from your display-manager";
      default = { };
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "GameScope Session";
          args = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Arguments to be passed to GameScope for the session.
            '';
          };

          env = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = ''
              Environmental variables to be passed to GameScope for the session.
            '';
          };

          steamArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "-tenfoot"
              "-pipewire-dmabuf"
            ];
            description = ''
              Arguments to be passed to Steam for the session.
            '';
          };
        };
      };
    };

    extest.enable = lib.mkEnableOption ''
      Load the extest library into Steam, to translate X11 input events to
      uinput events (e.g. for using Steam Input on Wayland)
    '';

    protontricks = {
      enable = lib.mkEnableOption "protontricks, a simple wrapper for running Winetricks commands for Proton-enabled games";
      package = lib.mkPackageOption pkgs "protontricks" { };
    };

    hardware.enable = lib.mkEnableOption "Enable udev rules for Steam hardware such as the Steam Controller, other supported controllers and the HTC Vive. Requires a udev-compatible device manager.";
  };

  config = lib.mkIf cfg.enable {
    hardware.graphics = {
      # this fixes the "glXChooseVisual failed" bug, context: https://github.com/NixOS/nixpkgs/issues/47932
      enable = true;
      enable32Bit = true;
    };

    programs.steam.extraPackages = cfg.fontPackages;
    programs.gamescope.enable = lib.mkDefault cfg.gamescopeSession.enable;

    services.dbus.enable = true;

    environment.systemPackages = [
      (lib.hiPrio gamescopeSessionFile)
      cfg.package
      cfg.package.run
    ]
    ++ lib.optional cfg.gamescopeSession.enable steam-gamescope
    ++ lib.optional cfg.protontricks.enable (
      cfg.protontricks.package.override { inherit extraCompatPaths; }
    );

    services.udev.packages = lib.mkIf cfg.hardware.enable [
      pkgs.steam-devices-udev-rules
    ];
    boot.kernelModules = lib.mkIf cfg.hardware.enable [ "uinput" ];
  };
}
