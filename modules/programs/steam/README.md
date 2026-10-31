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

## Configuring games

`programs.steam.apps` configures games in your library by app ID, and adds non-Steam
games ("Add a Non-Steam Game") as shortcuts. Both take the same per-game options:

```nix
programs.steam.apps = {
  dota = {
    appId = 570;
    launchOptions = "-novid %command%";
    compatTool = "proton_9";
    autoUpdate = "onLaunch";
  };
  retroarch = {
    shortcut.exe = "/run/current-system/sw/bin/retroarch";
    artwork.grid = ./retroarch-capsule.png;
  };
};
```

With any app set, the installed `steam` is a wrapper that merges these into Steam's
config files and then starts Steam. Things to know:

- Settings are written for every account that has logged in on the machine once, and
  take effect from the next start after that.
- Nothing is written while Steam is running, since it rewrites these files when it
  exits. Close Steam fully, not just its window, for a change to apply.
- Options left at `null` are Steam's. One that is set wins over whatever is picked in
  Steam, on every start. Unsetting it leaves the last value in place.
- `autoUpdate` lives in the game's app manifest, so it applies once the game is
  installed. `cloudSync` is synced by Steam Cloud, so another machine can sync a
  different value back.
- A shortcut's app ID is computed from its exe and name. When that changes - a new
  store path after an update, say - the old entry is replaced, with its Proton mapping
  and artwork. Steam Input layouts and play time are not carried over, so prefer an
  `exe` that stays put, like `/run/current-system/sw/bin/<name>`.
- The first time a file is changed, a `.steam-apply.bak` copy is kept next to it.
- Anything without an option of its own goes in `extraSettings`.

### Games with an installer

A Windows game that comes as an installer - a launcher like HoYoPlay, say - takes an
`installer` instead of `shortcut.exe`:

```nix
programs.steam.apps.genshin = {
  shortcut.appName = "Genshin Impact";
  compatTool = "GE-Proton";
  installer = {
    url = "https://example.com/Setup.exe";
    game = "drive_c/Program Files/HoYoPlay/launcher.exe";
  };
};
```

The shortcut points at `game` in a prefix of its own, at
`<steam root>/steamapps/nonsteam/<name>/pfx`. Its first launch downloads `url` into
`nonsteam/<name>/installer/` and runs it through Steam's own Proton in that prefix, then
starts the game; later launches start the game straight away. The path never changes,
so neither does the shortcut's app ID. Removing the app removes the shortcut but keeps
`nonsteam/<name>/`, which holds the install and its saves.

Settings are merged by `steam-apply`, ported from
[nixos-steam](https://github.com/parzivale/nixos-steam), which documents where Steam
keeps each of them.
