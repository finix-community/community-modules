# `dinit.services` - the system half of the module
#
# these land in /etc/dinit.d, where a dinit running as the system service
# manager would find them. finix runs finit as pid 1, so on a finix host they
# are written and then nothing picks them up; see tests/user-services.nix for
# the half that is actually supervised here.
{
  note = "system-level dinit services; finit is pid 1 on finix, so nothing supervises them - the user half is booted in tests/user-services.nix";

  machine =
    { pkgs, ... }:
    {
      dinit.services.compat-system-probe = {
        type = "process";
        command = "${pkgs.coreutils}/bin/sleep 3600";
        run-as = "nobody";
        restart = "on-failure";
        log-type = "file";
        logfile = "/var/log/compat-system-probe.log";
      };
    };
}
