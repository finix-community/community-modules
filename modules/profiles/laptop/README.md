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

  networking.hostName = "mylaptop";

  programs.niri.enable = true;

  environment.systemPackages = with pkgs; [
    foot        # terminal
    fuzzel      # launcher
  ];

  users.users.lennart = {
    isNormalUser = true;
    extraGroups =
      [ "wheel" "video" "audio" ]
      ++ lib.optionals config.services.networkmanager.enable [ "networkmanager" ]
      ++ lib.optionals config.services.seatd.enable [ config.services.seatd.group ];

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
- session: `greetd` + `regreet`, `dbus`, `polkit`, `sudo`, `rtkit`, `xdg` (autostart/icons/mime/portal)
- audio: `pipewire` + `wireplumber`, `@audio` rtprio/nice/memlock limits
- graphics: `hardware.graphics`, `fontconfig` + default fonts
- firmware: `linux-firmware`, `sof-firmware`, `wireless-regdb`
- networking: `nftables` firewall (drop input; allow established, lo, icmp, ssh:22)
- power/hardware: `upower`, `power-profiles-daemon`, `brightnessctl`, `bluetooth`, `zzz`
- system: `chrony`, `sysklogd`, `fcron`, `earlyoom`, `nix-daemon`, `nixos-rebuild-ng`
- editor: `nano` (default; override with another `programs.<editor>.enable`)

## Picking a stack

Two parallel stacks, switched by device manager:

| | device mgr | seat mgr | wifi |
|---|---|---|---|
| `"standard"` | `udev` | `elogind` | `NetworkManager` |
| `"minimal"` | `mdevd` | `seatd` | `iwd` |

Flip with:

```nix
profiles.laptop.hardwareSupport = "standard";
profiles.laptop.hardwareSupport = "minimal"
```

Assertions enforce no cross-mixing. With `seatd`, the profile also wires up `providers.privileges.rules` for `poweroff`/`reboot`/`zzz` and adds the `seatd` group to `rtkit` + `power-profiles-daemon`.

Pick `udev` (default) if you want:

- maximum hardware compatibility
- to use `NetworkManager` (GUI applets, VPN plugins, captive-portal handling)
- the least surprise - matches the rest of the nixos ecosystem
- `elogind` to handle session/seat management, suspend-on-lid, power button, etc. for free

Pick `mdevd` if you want:

- to avoid pulling in any of the `systemd` codebase (`eudev` is a fork of the `systemd` component)
- a smaller, faster device manager - `mdevd` is from the skarnet/`s6` family
- to stay close to a minimalist system
- `iwd`'s lighter-weight wifi management instead of `NetworkManager`

## Overriding

Most options use `lib.mkDefault`, so disable anything you don't want:

```nix
services.bluetooth.enable = false;
programs.zzz.enable = false;
```
