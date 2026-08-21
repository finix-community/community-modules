{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.river;

  # gardendevd needs libudev-garden; mdevd/keventd need libudev-zero.
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

  wlroots_0_20 = pkgs.wlroots_0_20.override {
    inherit libinput;
  };

  river = pkgs.river.override (
    lib.optionalAttrs (udevApi != null) {
      inherit libinput wlroots_0_20;
      udev = udevApi;
    }
  );

  initScript = pkgs.writeShellScriptBin "river-init" cfg.init;

  sessionFile = pkgs.writeTextDir "share/wayland-sessions/${cfg.sessionName}.desktop" ''
    [Desktop Entry]
    Name=River
    Comment=River Wayland compositor
    Exec=${pkgs.dbus}/bin/dbus-run-session -- ${lib.getExe cfg.package} -c ${lib.getExe initScript}
    TryExec=${lib.getExe cfg.package}
    Type=Application
    DesktopNames=river
  '';
in
{
  options.programs.river = {
    enable = lib.mkEnableOption "River Wayland compositor";

    package = lib.mkOption {
      type = lib.types.package;
      default = river;
      defaultText = lib.literalExpression "pkgs.river";
      description = "The River package to use.";
    };

    init = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Shell script run when River starts. It should start a River-compatible
        window manager and any other session programs.
      '';
    };

    sessionName = lib.mkOption {
      type = lib.types.str;
      default = "river";
      description = "Filename, without .desktop, for the display-manager session.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.init != "";
            message = "programs.river.init must be set when River is enabled.";
          }
        ];

        environment.systemPackages = [ cfg.package ];
      }

      (lib.mkIf (cfg.init != "") {
        environment.systemPackages = [
          initScript

          # Override River's built-in session with one that starts the init script.
          (lib.hiPrio sessionFile)
        ];
      })
    ]
  );
}
