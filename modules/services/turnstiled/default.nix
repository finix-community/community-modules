{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.turnstiled;

  package = pkgs.callPackage ./package.nix { graphicalMonitor = cfg.dinit.enableGraphicalMonitor; };
in
{
  options.services.turnstiled = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable [turnstilel](${cfg.package.meta.homepage}).
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      description = ''
        The package to use for `turnstile`.
      '';
    };

		configFile = lib.mkOption {
			type = lib.types.path;
			default = "/etc/turnstiled.conf";
			description = "Configuration file location for tunrstiled";
		};

		systemBootDir = lib.mkOption {
			type = lib.types.path;
			default = "/usr/lib/dinit.d/user/boot.d";
			description = "Location of boot services used for all users";
		};

		settings = with lib; mkOption {
			type = with types; submodule {
				options = {
					debug = mkOption {
						type = enum [ "yes" "no" ];
						default = "no";
						description = "Whether or not to enable debug output in turnstiled";
					};
					backend = mkOption {
						type = enum [ "dinit" "runit" ];
						default = "dinit";
						description = "`runit` is not currently supported, but changing this option may break things";
					};
					debug_stderr = mkOption {
						type = enum [ "yes" "no" ];
						default = "no";
						description = "Whether or not to print debug to stderr in addition to stdout";
					};
					linger = mkOption {
						type = enum [ "yes" "no" ];
						default = "no";
						description = "Whether or not the service manager should linger after user logout. Requires ${cfg.settings.manage_rundir} to be enabled";
					};
					rundir_path = mkOption {
						type = str;
						default = "/run/user/%u";
						description = "Where the rundir is for the user. See [turnstiled](${cfg.package.meta.homepage}) documentation for available options";
					};
					manage_rundir = mkOption {
						type = enum [ "yes" "no" ];
						default = "no";
						description = "Whether or not `turnstiled` should manage the runtime directory";

					};
					export_dbus_address = mkOption {
						type = enum [ "yes" "no" ];
						default = "yes";
						description = "Whether or not to export the D-Bus session address to the environment of the service manager";
					};
					login_timeout = mkOption {
						type = ints.unsigned;
						default = 60;
						description = "How long the service manager waits on initial processes (in seconds) before giving up.";
					};
					root_session = mkOption {
						type = enum [ "yes" "no" ];
						default = "no";
						description = "Whether or not `turnstiled` acts for the root user.";
					};
				};
			};
		};

		dinit = with lib; mkOption {
			type = with types; submodule {
				options = {
					enable = mkOption {
						type = bool;
						default = true;
						description = "Whether or not to use the dinit backend for `turnstiled`.";
					};

					service_dir = mkOption {
						type = str;
						default = "$HOME/.config/dinit.d";
						description = "Users service dir for `turnstiled`'s `dinit` backend. This should include a way to differentiate per user unless all users have identical services.";
					};

					boot_dir = mkOption {
						type = str;
						default = "${cfg.dinit.service_dir}/boot.d";
						description = "Users service boot dir for `turnstiled`'s `dinit` backend. This should include a way to differentiate per user unless all users have identical services.";
					};
		
					system_boot_dir = mkOption {
						type = path;
						default = "/usr/lib/dinit.d/user/boot.d";
						description = "Systems service boot dir for `turnstiled`'s `dinit` backend.";
					};

					enableGraphicalMonitor = mkOption {
						type = bool;
						default = false;
						description = "Whether or not to monitor environment changes to DISPLAY and WAYLAND_DISPLAY variables. Currently requires manually adding `dinitctl setenv VAR=$VAR`to any startup scripts for your graphical environment to function.";
					};
				};
			};
		};
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ] ++ lib.lists.optional cfg.dinit.enable (lib.lowPrio pkgs.dinit);

		finit.tmpfiles.rules = [
			"d ${cfg.dinit.system_boot_dir} 0777"
		];

		environment.etc = {
			"turnstile/turnstiled.conf".text = ''
debug = ${cfg.settings.debug}
backend = ${cfg.settings.backend}
debug_stderr = ${cfg.settings.debug_stderr}
linger = ${cfg.settings.linger}
rundir_path = ${cfg.settings.rundir_path}
manage_rundir = ${cfg.settings.manage_rundir}
export_dbus_address = ${cfg.settings.export_dbus_address}
login_timeout = ${toString cfg.settings.login_timeout}
root_session = ${cfg.settings.root_session}
			'';

			"turnstile/backend/dinit.conf".text = ''
boot_dir="${cfg.dinit.boot_dir}"
system_boot_dir="${cfg.dinit.system_boot_dir}"
services_dir1="${cfg.dinit.service_dir}"
services_dir2="/etc/dinit.d/user"
services_dir3="/usr/local/lib/dinit.d/user"
services_dir4="/usr/lib/dinit.d/user"
			'';

			"pam.d/turnstiled".text = ''auth		sufficient	pam_rootok.so
session		optional	pam_keyinit.so force revoke
session		optional	pam_umask.so usergroups umask=022
-session	optional	pam_elogind.so
session		required  pam_env.so conffile=/etc/security/pam_env.conf readenv=1 # env (order 10100)
session		required	${cfg.package}/pam/pam_turnstile.so turnstiled
session		required	pam_limits.so
'';
		};

		security.pam.services = lib.mkMerge [ 
			{
				login.text = lib.mkAfter "session optional ${cfg.package}/pam/pam_turnstile.so";
			}
		];

    finit.services.turnstiled = {
      description = "turnstiled, a user-service manager manager";
      command = "${cfg.package}/bin/turnstiled";
      conditions = "service/syslogd/ready";
      log = true;
			pid = "/run/turnstiled.pid";
			path = with pkgs; [ cfg.package coreutils ] ++ lib.lists.optional cfg.dinit.enable (lib.lowPrio dinit);
    };
  };
}
