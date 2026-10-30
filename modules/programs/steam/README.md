# `steam`

Community module for `steam`. Currently sets up the following: 

- video drivers
- `steam` package

Also allows for extra configuration like environment variables, package overrides, etc.

## Wrapping every game

`programs.steam.gameWrappers` runs every game through a chain of programs, without
touching any game's launch options. Entries go outermost first, and each one is
given the rest of the chain and then the game's command as its arguments:

```nix
programs.steam.gameWrappers = [
  [ "${lib.getExe pkgs.gamescope}" "-f" "--" ]
  "${pkgs.gamemode}/bin/gamemoderun"
];
```

A wrapper of your own is a script that ends in `exec "$@"`:

```nix
programs.steam.gameWrappers = [
  (pkgs.writeShellScript "notify" ''
    ${pkgs.libnotify}/bin/notify-send "launching $SteamAppId"
    exec "$@"
  '')
];
```

Things to know:

- Wrappers run inside steam's FHS sandbox, after steam has built the game's
  environment, so `SteamAppId` and the game's own launch options are already set.
- The list is the same for every game. Anything decided per game - skipping
  gamescope for one title, say - goes inside a script entry, which can look at
  `SteamAppId` and `exec` differently.
- Put whatever opens a display (gamescope) first, with `lib.mkBefore` when entries
  come from different modules. gamescope starts the game as its child rather than
  `exec`ing it, so a wrapper that relies on its own PID being the game's (for example
  `gamemoded -r$$`) has to come before it.
