# preservation

Declarative management of non-volatile system state for finix systems using finit as PID 1.

Inspired by [impermanence](https://github.com/nix-community/impermanence), but not a drop-in replacement. Instead of relying on shell interpreters, preservation generates a pure initrd script that runs bind mounts and symlinks via finit after, gated on the mount task of each preserved root — making it compatible with interpreter-free finix systems.

## Basic usage

```nix
{
  preservation = {
    enable = true;
    preserveAt."/state" = {
      directories = [ "/var/lib/someservice" ];
      files = [ "/etc/machine-id" ];
      users.alice.directories = [ ".config/someapp" ];
    };
  };
}
```

## Prerequisites

Requires at least nixos-24.11.
