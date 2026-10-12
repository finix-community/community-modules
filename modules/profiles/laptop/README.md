# `laptop` profile

A configurable `finix` starting point for a personal laptop. Provides defaults for init, audio, networking, power and login without requiring a fixed stack.

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

  users.users.someone = {
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
- editor: `nano` (disable it when choosing another editor)

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

The table describes defaults, not mandatory combinations. The profile warns about potentially conflicting managers instead of rejecting custom stacks.
Core module constraints still apply; some device managers conflict when enabled together.
`sessiond` and `sessiond-uaccess` are enabled by default for the `keventd`, `udev`, and `gardendevd` stacks.
When neither `elogind` nor `sessiond` is enabled, the profile adds the legacy `seatd` privilege rules for `poweroff`/`reboot`/`zzz` and 
grants the required hardware groups. 
The `seatd` group is still added when `seatd` is enabled so compositors can access its socket.

Enabling `elogind` disables the profile's default `sessiond` and `seatd` selection. 
`sessiond-uaccess` follows `services.sessiond.enable`, it can also
be disabled independently. 
Both can be enabled explicitly on a custom stack, including `mdevd`.

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
NetworkManager is normally paired with `udev` or `gardendevd` because of its
udev integration. For a custom backend, check package support and runtime behavior.

## Overriding

Profile service choices and scalar settings use `lib.mkDefault`. Normal definitions override them without `mkForce`:

```nix
services.bluetooth.enable = false;
programs.limine.enable = false; # bring your own bootloader
programs.regreet.enable = false; # bring your own login manager
programs.wireplumber.enable = false;
programs.pipewire.enable = false;
programs.nano.enable = false;
programs.zzz.enable = false;
finit.runlevel = 2;
providers.firewall.allowedTCPPorts = [];
profiles.laptop.packages = []; # omit nixos-rebuild-ng, retain core packages
users.users.someone.extraGroups = [ "wheel" ]; # replace suggested groups
```

List defaults (firmware, ports, user groups and earlyoom arguments) are replaced by a normal definition. 
To extend one, repeat the wanted defaults in your list.
Privilege rules remain additive to preserve rules from other modules, use `lib.mkForce` to replace the complete list, accounting for those modules too.
Kernel parameters also merge: an explicit `loglevel` follows the profile's quiet-boot default. 
Use `lib.mkForce` only to replace the whole kernel-parameter list.

Disabling a dependency may require disabling its consumers: core enables
PipeWire for WirePlumber, greetd for ReGreet, and D-Bus/polkit for sessiond.
Core also requires at least one TTY; when disabling getty, provide your own `finit.ttys`. 
Logging-dependent services need a `syslogd` readiness condition from the chosen logging setup. 
Disabling a profile default does not implement its replacement or remove these core requirements.

Temporary-file cleaning follows the selected scheduler backend; disabling fcron
does not require disabling cleaning if another scheduler is configured.
