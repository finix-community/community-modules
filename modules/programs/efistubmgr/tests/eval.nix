# efistubmgr's whole job is UEFI NVRAM manipulation - its install hook calls
# `efistubmgr create/list/delete` against /sys/firmware/efi/efivars - and
# finix's qemu test driver has no UEFI firmware support to give it that
# (virtualisation.qemu.bootMode is `kernel`-only; `bios`/`uefi` are not
# implemented yet). so this is eval-only.
#
# one config is enough to catch drift across the whole module: every
# `${...}` the install hook script interpolates - coreutils, awk, sbctl,
# boot.loader.efi.efiSysMountPoint - is a nix-level interpolation evaluated
# unconditionally when the derivation is instantiated, regardless of which
# shell `if` branch (like secureBoot.enable) it ends up inside.
{
  machine = {
    programs.efistubmgr.enable = true;
  };

  note = "finix's qemu test driver only supports kernel/direct-boot vms - there is no /sys/firmware/efi/efivars for the install hook's NVRAM operations to act on";
}
