# `minimal` profile

Minimal tty/server profile for finix.

## Usage

```nix
{
  inputs.finix.url = "github:finix-community/finix";
  inputs.community-modules.url = "github:finix-community/community-modules";

  outputs = { nixpkgs, finix, community-modules, ... }: {
    nixosConfigurations.myConfiguration = finix.lib.nixosSystem {
      modules = [
        community-modules.nixosModules.minimal
        ./configuration.nix
        {
          profiles.minimal = enable;
          profiles.minimal.deviceManager = "mdevd" or "udev";
          profiles.minimal.withFlakes = true; #(if you want to use flakes)
        }
        { nixpkgs.pkgs = import nixpkgs { system = "x86_64-linux"; }; }
      ];
    };
  };
}
```

## What's included

- boot/init: device manager (udev or mdevd)
- networking: dhcpcd
- system: nix-daemon (with flakes), sysklogd, bash
- package: nixos-rebuild-ng
- sudo: if you use it (optional)
