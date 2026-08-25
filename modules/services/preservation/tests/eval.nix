{
  note = "acts from the initrd against a persistent volume; the test vm boots on a tmpfs root with no second volume to preserve to";

  machine = {
    preservation.enable = true;
    preservation.preserveAt."/persist" = {
      directories = [ "/var/lib/compat" ];
      files = [ "/etc/machine-id" ];
    };

    fileSystems."/persist" = {
      device = "/dev/disk/by-label/persist";
      fsType = "ext4";
      neededForBoot = true;
    };
  };
}
