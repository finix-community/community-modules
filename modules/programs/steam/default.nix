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

  # With STEAM_GAME_LAUNCH_SHELL set, steam runs `$STEAM_GAME_LAUNCH_SHELL "<command line>"`
  # instead of `/bin/sh -c "<command line>"` - the `-c` is only added on the /bin/sh path,
  # so the command line arrives as `$1` and the `-c` is supplied here.
  gameLaunchShell = pkgs.writeShellScript "steam-game-launch-shell" ''
    exec ${
      lib.concatMapStringsSep " " (wrapper: lib.escapeShellArgs (lib.toList wrapper)) cfg.gameWrappers
    } /bin/sh -c "$1"
  '';

  steam-apply = pkgs.callPackage ./steam-apply/package.nix { };

  # Where Steam keeps each per-app option. `<appid>` is filled in by steam-apply, which is
  # what computes a shortcut's app ID. A shortcut's launch options and overlay switch live
  # in its shortcuts.vdf entry instead, so they go there.
  appSettings =
    app:
    let
      bool = v: if v then "1" else "0";
      compat = "Software/Valve/Steam/CompatToolMapping/<appid>";
      local = path: value: {
        file = "localconfig";
        inherit path value;
      };
    in
    lib.optionals (app.compatTool != null) [
      {
        file = "config";
        path = "${compat}/name";
        value = app.compatTool;
      }
      {
        file = "config";
        path = "${compat}/config";
        value = app.compatToolConfig;
      }
      {
        file = "config";
        path = "${compat}/priority";
        value = "250";
      }
    ]
    ++ lib.optional (app.shortcut == null && app.launchOptions != null) (
      local "Software/Valve/Steam/apps/<appid>/LaunchOptions" app.launchOptions
    )
    ++ lib.optional (app.shortcut == null && app.overlay != null) (
      local "apps/<appid>/OverlayAppEnable" (bool app.overlay)
    )
    ++ lib.optional (app.steamInput != null) (
      local "apps/<appid>/UseSteamControllerConfig"
        {
          disable = "0";
          default = "1";
          enable = "2";
        }
        .${app.steamInput}
    )
    ++ lib.optional (app.autoUpdate != null) {
      file = "appmanifest";
      path = "AutoUpdateBehavior";
      value =
        {
          default = "0";
          onLaunch = "1";
          highPriority = "2";
          always = "3";
        }
        .${app.autoUpdate};
    }
    ++ lib.optional (app.cloudSync != null) {
      file = "sharedconfig";
      path = "Software/Valve/Steam/apps/<appid>/cloudenabled";
      value = bool app.cloudSync;
    }
    ++ app.extraSettings;

  # Put in front of `%command%` by steam-apply, as `<this> <dir> %command%`, for an app with an
  # installer. `%command%` is the whole chain steam built - reaper, runtime, then the compat
  # tool running the game's exe - so this runs before any of it, and everything after inherits
  # the prefix it pins. Until the game is there, the same chain is run once with the
  # installer's path in place of the game's, so steam's own Proton installs it.
  installShim =
    name: installer:
    let
      file = lib.head (lib.splitString "?" (baseNameOf installer.url));
    in
    pkgs.writeShellScript "steam-install-${name}" ''
      dir=$1
      shift
      game="$dir/pfx/"${lib.escapeShellArg installer.game}
      export STEAM_COMPAT_DATA_PATH="$dir"

      if [ ! -s "$game" ]; then
        setup="$dir/installer/"${lib.escapeShellArg file}
        if [ ! -s "$setup" ]; then
          mkdir -p "$dir/installer"
          echo "steam-install: downloading "${lib.escapeShellArg installer.url} >&2
          ${lib.getExe pkgs.curl} -fL --retry 3 -o "$setup.part" ${lib.escapeShellArg installer.url} \
            && mv "$setup.part" "$setup" \
            || { echo "steam-install: download failed" >&2; exit 1; }
        fi

        found=
        command=()
        for arg in "$@"; do
          if [ "$arg" = "$game" ]; then
            command+=("$setup")
            found=1
          else
            command+=("$arg")
          fi
        done
        if [ -z "$found" ]; then
          echo "steam-install: $game is not in the command line: $*" >&2
          exit 1
        fi
        "''${command[@]}"

        if [ ! -s "$game" ]; then
          echo "steam-install: the installer finished, but $game is not there" >&2
          exit 1
        fi
      fi

      cd "$(dirname "$game")" || exit 1
      exec "$@"
    '';

  appsJson = pkgs.writeText "steam-apps.json" (
    builtins.toJSON {
      apps = lib.mapAttrsToList (key: app: {
        inherit key;
        inherit (app) appId;
        shortcut =
          if app.shortcut == null then
            null
          else
            app.shortcut
            // {
              launchOptions = if app.launchOptions == null then "" else app.launchOptions;
              allowOverlay = if app.overlay == null then true else app.overlay;
              installer =
                if app.installer == null then
                  null
                else
                  {
                    shim = "${installShim key app.installer}";
                    inherit (app.installer) game;
                  };
            };
        settings = appSettings app;
        artwork = lib.mapAttrs (_: v: if v == null then null else "${v}") app.artwork;
      }) cfg.apps;
    }
  );

  # steam with `programs.steam.apps` merged into its config files on every start. It runs on
  # the host, before the FHS sandbox is entered, and only for `steam` itself - not for
  # `steam-run`, which shares the sandbox's profile.
  steamWithApps = pkgs.symlinkJoin {
    name = "${cfg.package.name}-with-apps";
    paths = [ cfg.package ];
    postBuild = ''
      rm $out/bin/steam
      ln -s ${pkgs.writeShellScript "steam" ''
        ${lib.getExe steam-apply} ${appsJson} || echo "steam: applying programs.steam.apps failed" >&2
        exec ${cfg.package}/bin/steam "$@"
      ''} $out/bin/steam
    '';
    inherit (cfg.package) passthru meta;
  };

in
{
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
            // (lib.optionalAttrs (cfg.gameWrappers != [ ]) {
              STEAM_GAME_LAUNCH_SHELL = "${gameLaunchShell}";
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
    remotePlay.openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open ports in the firewall for Steam Remote Play.
      '';
    };

    dedicatedServer.openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open ports in the firewall for Source Dedicated Server.
      '';
    };

    localNetworkGameTransfers.openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open ports in the firewall for Steam Local Network Game Transfers.
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

    gameWrappers = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.path (lib.types.nonEmptyListOf lib.types.str));
      default = [ ];
      example = lib.literalExpression ''
        [
          [ "''${lib.getExe pkgs.gamescope}" "-f" "--" ]
          "''${pkgs.gamemode}/bin/gamemoderun"
        ]
      '';
      description = ''
        Programs every game is launched through, outermost first. Each entry is a
        program, or a program and its arguments, and is given the rest of the chain
        followed by the game's command line as its arguments, as with launch options'
        `<wrapper> %command%` - so each must end in running `"$@"`, and should `exec` it.

        The list is the same for every game; anything decided per game belongs inside a
        script entry of its own. Entries set by different modules are ordered with
        `lib.mkBefore`/`lib.mkAfter`.
      '';
    };

    apps = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, config, ... }:
          {
            config.shortcut = lib.mkIf (config.installer != null) { };

            options = {
              appId = lib.mkOption {
                type = lib.types.nullOr lib.types.ints.positive;
                default = null;
                example = 570;
                description = ''
                  The Steam app ID of a game in your library - the number in its store URL.
                  Exactly one of this and {option}`shortcut` is set.
                '';
              };

              shortcut = lib.mkOption {
                default = null;
                description = ''
                  Makes this a non-Steam game ("Add a Non-Steam Game"), written to
                  `userdata/<id>/config/shortcuts.vdf`. Steam gives a shortcut an app ID computed
                  from its exe and name, and every other option here follows that ID. When either
                  changes - a new store path after an update, say - the old entry is replaced along
                  with its compatibility tool mapping and artwork, so there are no duplicates.
                  Steam Input layouts and play time stay with the old ID, so an `exe` that does not
                  change on update, like `/run/current-system/sw/bin/<name>`, keeps them. Removing
                  the app removes the shortcut. Shortcuts added in Steam itself are never touched.
                '';
                type = lib.types.nullOr (
                  lib.types.submodule {
                    options = {
                      appName = lib.mkOption {
                        type = lib.types.str;
                        default = name;
                        defaultText = lib.literalMD "the attribute name";
                        description = "Name shown in the library.";
                      };
                      exe = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        example = "/run/current-system/sw/bin/retroarch";
                        description = ''
                          Absolute path of the program. Exactly one of this and
                          {option}`installer` is set.
                        '';
                      };
                      startDir = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = "Working directory; defaults to the directory of {option}`exe`.";
                      };
                      icon = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = "Path of an icon image.";
                      };
                      hidden = lib.mkOption {
                        type = lib.types.bool;
                        default = false;
                        description = "Hide the shortcut in the library.";
                      };
                      allowDesktopConfig = lib.mkOption {
                        type = lib.types.bool;
                        default = true;
                        description = "Use the Steam Input desktop configuration in the launcher.";
                      };
                      openVR = lib.mkOption {
                        type = lib.types.bool;
                        default = false;
                        description = "Mark the shortcut as a VR application.";
                      };
                      tags = lib.mkOption {
                        type = lib.types.listOf lib.types.str;
                        default = [ ];
                        description = "Library tags.";
                      };
                    };
                  }
                );
              };

              installer = lib.mkOption {
                default = null;
                description = ''
                  A Windows game that is installed by running its installer, rather than
                  pointed at with {option}`shortcut.exe`. This makes the app a shortcut to
                  {option}`game`, in a Wine prefix of its own at
                  `<steam root>/steamapps/nonsteam/<name>/pfx`, run with {option}`compatTool`.

                  The first launch downloads {option}`url` to
                  `<steam root>/steamapps/nonsteam/<name>/installer/` and runs it with that same
                  compatibility tool and prefix, then starts the game. The game starts in its own
                  directory. Removing the app removes the shortcut, but leaves the directory - the
                  install and its saves - in place.
                '';
                type = lib.types.nullOr (
                  lib.types.submodule {
                    options = {
                      url = lib.mkOption {
                        type = lib.types.str;
                        description = ''
                          Where to download the installer from. It is fetched at first launch
                          rather than at build time, so it needs no hash: launchers update
                          themselves after that, and their installer links tend to move.
                        '';
                      };
                      game = lib.mkOption {
                        type = lib.types.str;
                        example = "drive_c/Program Files/HoYoPlay/launcher.exe";
                        description = "The installed exe to launch, relative to the prefix.";
                      };
                    };
                  }
                );
              };

              launchOptions = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                example = "-novid %command%";
                description = "Launch options, as in Properties > General.";
              };

              compatTool = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                example = "proton_experimental";
                description = ''
                  Force a compatibility tool, as in Properties > Compatibility. This is the tool's
                  internal name: `proton_experimental`, `proton_9`, or the directory name of a tool
                  from {option}`programs.steam.extraCompatPackages`, such as `GE-Proton10-4`.
                '';
              };

              compatToolConfig = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Configuration string stored next to {option}`compatTool`; usually empty.";
              };

              overlay = lib.mkOption {
                type = lib.types.nullOr lib.types.bool;
                default = null;
                description = "Enable the Steam Overlay in game.";
              };

              steamInput = lib.mkOption {
                type = lib.types.nullOr (
                  lib.types.enum [
                    "default"
                    "disable"
                    "enable"
                  ]
                );
                default = null;
                description = "Override Steam Input for this game, as in Properties > Controller.";
              };

              autoUpdate = lib.mkOption {
                type = lib.types.nullOr (
                  lib.types.enum [
                    "default"
                    "onLaunch"
                    "highPriority"
                    "always"
                  ]
                );
                default = null;
                description = ''
                  When Steam updates this game, as in Properties > Updates. Stored in the game's
                  `appmanifest_<appid>.acf`, so it only takes effect once the game is installed.
                '';
              };

              cloudSync = lib.mkOption {
                type = lib.types.nullOr lib.types.bool;
                default = null;
                description = ''
                  Keep saves in Steam Cloud. This is stored in Steam's roaming config, which Steam
                  Cloud syncs itself, so another machine can sync a different value back.
                '';
              };

              artwork = lib.genAttrs [ "grid" "wide" "hero" "logo" "icon" ] (
                kind:
                lib.mkOption {
                  type = lib.types.nullOr lib.types.path;
                  default = null;
                  description = ''
                    Custom ${kind} image, as with "Set Custom Artwork". `grid` is the vertical
                    library capsule and `wide` the horizontal one.
                  '';
                }
              );

              extraSettings = lib.mkOption {
                type = lib.types.listOf (
                  lib.types.submodule {
                    options = {
                      file = lib.mkOption {
                        type = lib.types.enum [
                          "config"
                          "localconfig"
                          "sharedconfig"
                          "appmanifest"
                        ];
                        description = ''
                          The file the key lives in: `config/config.vdf`, a user's
                          `config/localconfig.vdf` or `7/remote/sharedconfig.vdf`, or the game's
                          `appmanifest_<appid>.acf`.
                        '';
                      };
                      path = lib.mkOption {
                        type = lib.types.str;
                        example = "Software/Valve/Steam/apps/<appid>/RPOEnable";
                        description = "Key path below the file's root key; `<appid>` is replaced with this app's ID.";
                      };
                      value = lib.mkOption {
                        type = lib.types.str;
                        description = "The value, as Steam stores it.";
                      };
                    };
                  }
                );
                default = [ ];
                description = "Keys without an option of their own, written as they are.";
              };
            };
          }
        )
      );
      default = { };
      example = lib.literalExpression ''
        {
          dota = {
            appId = 570;
            launchOptions = "-novid %command%";
            autoUpdate = "onLaunch";
          };
          retroarch = {
            shortcut.exe = "/run/current-system/sw/bin/retroarch";
            artwork.grid = ./retroarch-capsule.png;
          };
        }
      '';
      description = ''
        Games in your library, and non-Steam games, configured by Nix. Every time `steam` starts,
        the options set here are merged into Steam's config files, for every account that has
        logged in on this machine. Options left at `null` are left to Steam, and changing a set
        one in Steam is reverted on the next start. Unsetting an option leaves the last value in
        place rather than restoring Steam's default.

        Nothing is written while Steam is running, since it rewrites these files when it exits,
        and the first time a file is changed a `.steam-apply.bak` copy is kept next to it.
      '';
    };

    protontricks = {
      enable = lib.mkEnableOption "protontricks, a simple wrapper for running Winetricks commands for Proton-enabled games";
      package = lib.mkPackageOption pkgs "protontricks" { };
    };

    hardware.enable = lib.mkEnableOption "Enable udev rules for Steam hardware such as the Steam Controller, other supported controllers and the HTC Vive. Requires a udev-compatible device manager.";
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.concatLists (
      lib.mapAttrsToList (name: app: [
        {
          assertion = (app.appId == null) != (app.shortcut == null);
          message = "programs.steam.apps.${name}: set exactly one of `appId` and `shortcut`.";
        }
        {
          assertion =
            app.shortcut == null
            || (
              app.autoUpdate == null
              && app.cloudSync == null
              && lib.all (s: s.file != "appmanifest") app.extraSettings
            );
          message = "programs.steam.apps.${name}: a shortcut has no app manifest or Steam Cloud, so `autoUpdate`, `cloudSync` and appmanifest `extraSettings` do not apply.";
        }
        {
          assertion = app.shortcut == null || (app.shortcut.exe == null) != (app.installer == null);
          message = "programs.steam.apps.${name}: set exactly one of `shortcut.exe` and `installer`.";
        }
        {
          assertion = app.installer == null || app.compatTool != null;
          message = "programs.steam.apps.${name}: an `installer` runs through a compatibility tool, so set `compatTool`.";
        }
      ]) cfg.apps
    );

    hardware.graphics = {
      # this fixes the "glXChooseVisual failed" bug, context: https://github.com/NixOS/nixpkgs/issues/47932
      enable = true;
      enable32Bit = true;
    };

    programs.steam.extraPackages = cfg.fontPackages;
    programs.gamescope = lib.mkIf cfg.gamescopeSession.enable {
      enable = lib.mkDefault true;

      package = lib.mkDefault (
        pkgs.gamescope.override {
          libinput = pkgs.libinput.override {
            udev = config.programs.libudev.package;
            wacomSupport = false;
          };

          wlroots_0_19 = pkgs.wlroots_0_19.override {
            seatd = config.programs.libseat.package;
          };
        }
      );
    };

    services.dbus.enable = true;

    environment.systemPackages = [
      (if cfg.apps == { } then cfg.package else steamWithApps)
    ]
    ++ lib.optionals cfg.gamescopeSession.enable [
      steam-gamescope
      (lib.hiPrio gamescopeSessionFile)
    ]
    ++ lib.optional cfg.protontricks.enable (
      cfg.protontricks.package.override { inherit extraCompatPaths; }
    );

    services.udev.packages = lib.mkIf cfg.hardware.enable [
      pkgs.steam-devices-udev-rules
    ];
    boot.kernelModules = lib.mkIf cfg.hardware.enable [ "uinput" ];

    providers.firewall = lib.mkMerge [
      (lib.mkIf (cfg.remotePlay.openFirewall || cfg.localNetworkGameTransfers.openFirewall) {
        allowedUDPPorts = [ 27036 ]; # Peer discovery
      })

      (lib.mkIf cfg.remotePlay.openFirewall {
        # https://help.steampowered.com/en/faqs/view/3E3D-BE6B-787D-A5D2
        # https://help.steampowered.com/en/faqs/view/2EA8-4D75-DA21-31EB
        allowedTCPPorts = [
          27036
          27037
        ];
        allowedUDPPorts = [
          10400
          10401
        ];
        allowedUDPPortRanges = [
          {
            from = 27031;
            to = 27035;
          }
        ];
      })

      (lib.mkIf cfg.dedicatedServer.openFirewall {
        allowedTCPPorts = [ 27015 ]; # SRCDS Rcon port
        allowedUDPPorts = [ 27015 ]; # Gameplay traffic
      })

      (lib.mkIf cfg.localNetworkGameTransfers.openFirewall {
        allowedTCPPorts = [ 27040 ]; # Data transfers
      })
    ];

  };
}
