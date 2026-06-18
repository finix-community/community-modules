{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.programs.pipewire;

  format = pkgs.formats.json { };

  # Source the upstream config file into /etc/pipewire and, when settings are
  # given, drop our generated config into the matching `.conf.d` directory with
  # a high-priority `99-` prefix so it overrides anything shipped by the package.
  pipewireConf =
    file: settings:
    {
      "pipewire/${file}".source = "${cfg.package}/share/pipewire/${file}";
    }
    // lib.optionalAttrs (settings != { }) {
      "pipewire/${file}.d/99-nix.conf".source = format.generate "99-nix.conf" settings;
    };

  enable32BitAlsaPlugins =
    cfg.alsa.support32Bit && pkgs.stdenv.hostPlatform.isx86_64 && pkgs.pkgsi686Linux.pipewire != null;

  pipewire' =
    (pkgs.pipewire.override (
      lib.optionalAttrs config.services.mdevd.enable {
        enableSystemd = false;
        udev = pkgs.libudev-zero;
      }
    )).overrideAttrs
      (o: {
        # https://gitlab.freedesktop.org/pipewire/pipewire/-/issues/2398#note_2967898
        patches = o.patches or [ ] ++ lib.optionals config.services.mdevd.enable [ ./pipewire.patch ];
      });

  pipewire32' =
    (pkgs.pkgsi686Linux.pipewire.override (
      lib.optionalAttrs config.services.mdevd.enable {
        enableSystemd = false;
        udev = pkgs.libudev-zero;
      }
    )).overrideAttrs
      (o: {
        patches = o.patches or [ ] ++ lib.optionals config.services.mdevd.enable [ ./pipewire.patch ];
      });

  # The package doesn't output to $out/lib/pipewire directly so that the
  # overlays can use the outputs to replace the originals in FHS environments.
  #
  # This doesn't work in general because of missing development information.
  jack-libs = pkgs.runCommand "jack-libs" { } ''
    mkdir -p "$out/lib"
    ln -s "${cfg.package.jack}/lib" "$out/lib/pipewire"
  '';

  lv2Plugins = pkgs.buildEnv {
    name = "pipewire-lv2-plugins";
    paths = cfg.extraLv2Packages;
    pathsToLink = [ "/lib/lv2" ];
  };

  ladspaPlugins = pkgs.buildEnv {
    name = "pipewire-ladspa-plugins";
    paths = cfg.extraLadspaPackages;
    pathsToLink = [ "/lib/ladspa" ];
  };

in
{
  options.programs.pipewire = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable [pipewire](${pkgs.pipewire.meta.homepage}).
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pipewire';
      defaultText = lib.literalExpression "pkgs.pipewire";
      description = ''
        The package to use for `pipewire`.
      '';
    };

    alsa = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to enable PipeWire-ALSA support.";
      };
      support32Bit = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to enable 32-bit ALSA support on 64-bit systems.";
      };
    };

    jack = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to enable JACK audio emulation.";
      };

      settings = lib.mkOption {
        type = format.type;
        default = { };
        example = {
          "jack.properties" = {
            "jack.show-midi" = false;
          };
        };
        description = ''
          Configuration for the PipeWire JACK server and client library.

          This is written to `/etc/pipewire/jack.conf.d/99-nix.conf` as a
          high-priority drop-in over the package defaults in
          `/etc/pipewire/jack.conf`.

          See the [PipeWire wiki][wiki] for examples.

          [wiki]: https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Config-JACK
        '';
      };
    };

    # TODO need networking.firewall to properly port over nixos/pipewire rapOpenFirewall option

    settings = lib.mkOption {
      type = format.type;
      default = { };
      example = {
        "context.properties" = {
          "default.clock.rate" = 44100;
        };
        "stream.properties" = {
          "channelmix.upmix" = false;
        };
      };
      description = ''
        Configuration for the PipeWire server.

        This is written to `/etc/pipewire/pipewire.conf.d/99-nix.conf` as a
        high-priority drop-in over the package defaults in
        `/etc/pipewire/pipewire.conf`.

        See `man pipewire.conf` for details, and [the PipeWire wiki][wiki] for examples.

        See also:
        - [PipeWire wiki - virtual devices][wiki-virtual-device] for creating virtual devices or remapping channels
        - [PipeWire wiki - filter-chain][wiki-filter-chain] for creating more complex processing pipelines
        - [PipeWire wiki - network][wiki-network] for streaming audio over a network

        [wiki]: https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Config-PipeWire
        [wiki-virtual-device]: https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Virtual-Devices
        [wiki-filter-chain]: https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Filter-Chain
        [wiki-network]: https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Network
      '';
    };

    client = {
      settings = lib.mkOption {
        type = format.type;
        default = { };
        example = {
          "stream.properties" = {
            "resample.disable" = true;
          };
        };
        description = ''
          Configuration for the PipeWire client library, used by most applications.

          This is written to `/etc/pipewire/client.conf.d/99-nix.conf` as a
          high-priority drop-in over the package defaults in
          `/etc/pipewire/client.conf`.

          See the [PipeWire wiki][wiki] for examples.

          [wiki]: https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Config-client
        '';
      };
    };

    pulse = {
      settings = lib.mkOption {
        type = format.type;
        default = { };
        example = {
          "pulse.rules" = [
            {
              matches = [
                { "application.process.binary" = "my-broken-app"; }
              ];
              actions = {
                quirks = [ "force-s16-info" ];
              };
            }
          ];
        };
        description = ''
          Configuration for the PipeWire PulseAudio server.

          This is written to `/etc/pipewire/pipewire-pulse.conf.d/99-nix.conf` as a
          high-priority drop-in over the package defaults in
          `/etc/pipewire/pipewire-pulse.conf`.

          See `man pipewire-pulse.conf` for details, and [the PipeWire wiki][wiki] for examples.

          See also:
          - [PipeWire wiki - PulseAudio tricks guide][wiki-tricks] for more examples.

          [wiki]: https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Config-PulseAudio
          [wiki-tricks]: https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Guide-PulseAudio-Tricks
        '';
      };
    };

    extraLv2Packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.lsp-plugins ]";
      description = ''
        List of packages that provide LV2 plugins in `lib/lv2` that should
        be made available to PipeWire for [filter chains][wiki-filter-chain].

        [wiki-filter-chain]: https://docs.pipewire.org/page_module_filter_chain.html
      '';
    };

    extraLadspaPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.noisetorch-ladspa ]";
      description = ''
        List of packages that provide LADSPA plugins in `lib/ladspa` that should
        be made available to PipeWire for [filter chains][wiki-filter-chain].

        [wiki-filter-chain]: https://docs.pipewire.org/page_module_filter_chain.html
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
    ]
    ++ lib.optionals cfg.jack.enable [ jack-libs ];

    services.udev.packages = [ cfg.package ];
    services.mdevd.hotplugRules = lib.mkIf cfg.alsa.enable (
      lib.mkAfter ''
        # alsa sound devices and audio stuff
        pcm.*       root:audio 0660 =snd/
        control.*   root:audio 0660 =snd/
        midi.*      root:audio 0660 =snd/
        seq         root:audio 0660 =snd/
        timer       root:audio 0660 =snd/

        adsp        root:audio 0660 >sound/
        audio       root:audio 0660 >sound/
        dsp         root:audio 0660 >sound/
        mixer       root:audio 0660 >sound/
        sequencer.* root:audio 0660 >sound/
      ''
    );

    environment.etc = {
      "security/limits.conf".text = ''
        @audio   -   rtprio     95
        @audio   -   nice       -19
        @audio   -   memlock    4194304
      '';

      "alsa/conf.d/49-pipewire-modules.conf" = lib.mkIf cfg.alsa.enable {
        text = ''
          pcm_type.pipewire {
            libs.native = ${cfg.package}/lib/alsa-lib/libasound_module_pcm_pipewire.so ;
            ${lib.optionalString enable32BitAlsaPlugins "libs.32Bit = ${pipewire32'}/lib/alsa-lib/libasound_module_pcm_pipewire.so ;"}
          }
          ctl_type.pipewire {
            libs.native = ${cfg.package}/lib/alsa-lib/libasound_module_ctl_pipewire.so ;
            ${lib.optionalString enable32BitAlsaPlugins "libs.32Bit = ${pipewire32'}/lib/alsa-lib/libasound_module_ctl_pipewire.so ;"}
          }
        '';
      };

      "alsa/conf.d/50-pipewire.conf" = lib.mkIf cfg.alsa.enable {
        source = "${cfg.package}/share/alsa/alsa.conf.d/50-pipewire.conf";
      };

      "alsa/conf.d/99-pipewire-default.conf" = lib.mkIf cfg.alsa.enable {
        source = "${cfg.package}/share/alsa/alsa.conf.d/99-pipewire-default.conf";
      };
    }
    // pipewireConf "pipewire.conf" cfg.settings
    // pipewireConf "client.conf" cfg.client.settings
    // pipewireConf "jack.conf" cfg.jack.settings
    // pipewireConf "pipewire-pulse.conf" cfg.pulse.settings;

    security.pam.environment = {
      LD_LIBRARY_PATH.default = lib.mkIf cfg.jack.enable [ "${cfg.package.jack}/lib" ];
      LV2_PATH.default = [ "${lv2Plugins}/lib/lv2" ];
      LADSPA_PATH.default = [ "${ladspaPlugins}/lib/ladspa" ];
    };
  };
}
