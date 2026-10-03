# `laptop` profile

An opinionated `finix` profile for a personal laptop. Covers the plumbing (init, audio, networking, power, login greeter, ...) so you can focus on the bits that vary per machine.

## Usage

Add this flake as an input and import the module:

```nix
{
  inputs.finix.url = "github:finix-community/finix";
  inputs.community-modules.url = "github:finix-community/community-modules";

  outputs = { nixpkgs, finix, community-modules, ... }: {
    nixosConfigurations.mylaptop = finix.lib.finixSystem {
      modules = [
        community-modules.nixosModules.laptop
        ./configuration.nix

        { nixpkgs.pkgs = nixpkgs.legacyPackages.x86_64-linux; }
      ];
    };
  };
}
```

You still need to bring your own:

- desktop environment / window manager / compositor
- user accounts
- host-specific hardware config (filesystems, kernel modules, etc.)

### Example

A minimal `configuration.nix` to put alongside the flake snippet above:

```nix
{ modules, config, lib, pkgs, ... }:
{
  imports = [
    modules.niri

    ./hardware-configuration.nix
  ];

  profiles.laptop.enable = true;
  profiles.laptop.user = "someone";

  networking.hostName = "mylaptop";

  programs.niri.enable = true;

  environment.systemPackages = with pkgs; [
    foot        # terminal
    fuzzel      # launcher
  ];

  users.users.lennart = {
    # finix has no plaintext passwords; `password` is the hashed form which you can generate with `mkpasswd`
    password = "$6$...";
  };
}
```

Generate `hardware-configuration.nix` for the target machine with:

```sh
nixos-generate-config --show-hardware-config > hardware-configuration.nix
```

The output assumes nixos, so review it and strip out anything that references modules or options `finix` doesn't ship.

## What's included

- boot/init: `finit` (runlevel 3), `limine`, `plymouth` splash screen
- session: `greetd` + `regreet`, `sessiond` + `sessiond-uaccess`, `dbus`, `polkit`, `sudo`, `rtkit`, `xdg` (autostart/icons/mime/portal)
- audio: `pipewire` + `wireplumber`, `@audio` rtprio/nice/memlock limits
- graphics: `hardware.graphics`, `fontconfig` + default fonts
- firmware: `linux-firmware`, `sof-firmware`, `wireless-regdb`
- networking: `nftables` firewall (drop input; allow established, lo, icmp, ssh:22)
- power/hardware: `upower`, `power-profiles-daemon`, `brightnessctl`, `bluetooth`, `zzz`
- system: `chrony`, `sysklogd`, `fcron`, `earlyoom`, `nix-daemon`, `nixos-rebuild-ng`
- editor: `nano` (default; override with another `programs.<editor>.enable`)

## Choosing device and network managers

The profile defaults to lightweight managers and derives its defaults from the services you enable. 
No profile-specific hardware enum is required:

| | device mgr | seat mgr | session mgr | wifi |
|---|---|---|---|---|
| default | `keventd` | `seatd` | `sessiond` | `iwd` |
| explicit `services.mdevd.enable` | `mdevd` | `seatd` | - | `iwd` |
| explicit `services.gardendevd.enable` | `gardendevd` | `seatd` | `sessiond` | `iwd` |
| explicit `services.udev.enable` | `udev` | `seatd` | `sessiond` | `iwd` |

For example, to use the full udev-compatible stack and NetworkManager:

```nix
services.udev.enable = true;
services.networkmanager.enable = true;
```

The profile requires exactly one device manager and exactly one of `iwd` and NetworkManager.
`sessiond` and `sessiond-uaccess` are enabled by default for the `keventd`, `udev`, and `gardendevd` stacks. With `seatd`, it wires up `providers.privileges.rules` for `poweroff`/`reboot`/`zzz` and
adds the `seatd` group to the primary user, `rtkit`, and `power-profiles-daemon`.

`elogind` remains available as an explicit alternative to `sessiond`; enable it
when using `udev` or `gardendevd` and disable `services.sessiond` and
`services.sessiond-uaccess` if you do not want both session stacks.

Pick `keventd` (default) if you want:

- a small, finit-native device manager
- udev-compatible rules without enabling eudev

Pick `udev` or `gardendevd` if you want:

- maximum hardware compatibility
- to use `NetworkManager` (GUI applets, VPN plugins, captive-portal handling)
- the least surprise - matches the rest of the nixos ecosystem
- `sessiond` + `sessiond-uaccess` for session power actions and device access

Pick `mdevd` if you want:

- a smaller, faster device manager - `mdevd` is from the skarnet/`s6` family
- to stay close to a minimalist system
- `iwd`'s lighter-weight wifi management instead of `NetworkManager`

NetworkManager can be selected explicitly with `services.networkmanager.enable = true;`, 
the profile then disables its default `iwd` selection. 
NetworkManager still needs `udev` or `gardendevd` because of its udev integration.

## Overriding

Most options use `lib.mkDefault`, so disable anything you don't want:

```nix
services.bluetooth.enable = false;
programs.zzz.enable = false;
```
