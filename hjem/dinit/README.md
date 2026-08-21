# `hjem` module for `dinit` user services

Accessed through:

```nix
hjem.users.<user>.dinit
```

`hjem.users.<user>.dinit.directory` is the directory files are written to
defaults to `$HOME/.config/dinit.d`

`hjem.users.<user>.dinit.services` is a `dinit` service whose available options
are described in [`options.nix`](./options.nix)

## Example Service

```nix
hjem.users.<user>.dinit.services = {
  pipewire = {
    type = "process";
    command = "${lib.getExe' config.programs.pipewire.package "pipewire"}";
    restart = true;
    depends-ms = [ "login.target" ];
  };
};
```
