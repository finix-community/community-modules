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

## Ownership and permissions

`user`, `group`, `mode`, `parent.*` and `mountOptions` are applied by the same
initrd script that sets up the bind mounts, so preserved state has the right
ownership from the very start of stage 2.

Because that runs before `userborn` allocates dynamic ids, every user and group
that owns preserved state needs a statically assigned id:

```nix
{
  users.users.someservice.uid = 900;
  users.groups.someservice.gid = 900;
}
```

The module asserts this, so a missing id is a build error rather than a
silently root-owned directory. State owned by `root` needs no configuration.

## Prerequisites

Requires at least nixos-24.11.
