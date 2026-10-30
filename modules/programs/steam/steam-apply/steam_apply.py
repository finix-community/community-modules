#!/usr/bin/env python3
"""Merge declarative per-app settings into Steam's config files.

steam-apply <apps.json>

Ported from nixos-steam's steam-config-apply (https://github.com/parzivale/nixos-steam). KeyValues, text and
binary, are read and written by `vdf` (https://github.com/ValvePython/vdf).

apps.json:
  {
    "apps": [
      {
        "key": "<attribute name>",
        "appId": 570 | null,            # null: a non-Steam shortcut, its app ID is computed from exe + name
        "shortcut": null | {"appName", "exe", "startDir", "icon", "launchOptions", "hidden",
                            "allowOverlay", "allowDesktopConfig", "openVR", "tags",
                            "installer": null | {"shim": "/nix/store/...", "game": "drive_c/.../game.exe"}},
        "settings": [{"file": "config|localconfig|sharedconfig|appmanifest", "path": "a/<appid>/b", "value": "<string>"}],
        "artwork": {"grid": "/nix/store/...png", ...}
      }
    ]
  }

Rules:
* Does nothing while Steam is running (pid in ~/.steam/steam.pid alive): Steam rewrites these files on exit.
* Only what is configured is written; everything else in each file is kept.
* Keys are matched case-insensitively (KeyValues semantics); existing key spelling is kept.
* A file that does not parse is left alone. Files are written atomically; the first time a file is modified a `.steam-apply.bak` copy is kept.
* A shortcut whose app ID changed (new exe path or name), or that is no longer configured, is removed together
  with its compatibility tool mapping and artwork. Shortcuts added in Steam itself are never touched.
* Per-user files are written for every account under userdata/ that has logged in at least once.
* appmanifest settings only apply to installed games.
* A shortcut with an installer points at its game in a prefix of its own, steamapps/nonsteam/<key>/pfx, with the
  installer's shim in front of `%command%`. Removing it leaves that directory alone.
"""
import json, os, sys, tempfile, zlib
from shlex import quote

import vdf

STATE = '.steam-apply-managed.json'
BAK = '.steam-apply.bak'
GRID_SUFFIX = {'grid': 'p', 'wide': '', 'hero': '_hero', 'logo': '_logo', 'icon': '_icon'}

# file -> (path relative to the Steam root or to userdata/<id>, root key, per user)
FILES = {
    'config': ('config/config.vdf', 'InstallConfigStore', False),
    'localconfig': ('config/localconfig.vdf', 'UserLocalConfigStore', True),
    'sharedconfig': ('7/remote/sharedconfig.vdf', 'UserRoamingConfigStore', True),
}


# ---------------------------------------------------------------- KeyValues
# Parsed with `vdf` into plain dicts, which keep the file's order. Steam matches keys case-insensitively, and `vdf`
# does not, so lookups go through `find`, which also keeps whatever spelling the file already has.
def find(d, key):
    """The key of `d` that is `key` to Steam, or None."""
    return next((k for k in d if k.lower() == key.lower()), None)


def set_path(d, path, value):
    """Set path to value (str); value None deletes the key (and its subtree) if present. Returns whether it changed."""
    for i, comp in enumerate(path):
        last = i == len(path) - 1
        k = find(d, comp)
        if value is None:
            if k is None or (not last and not isinstance(d[k], dict)):
                return False
            if last:
                del d[k]
                return True
        elif last:
            if k is not None and d[k] == value:
                return False
            d[comp if k is None else k] = value
            return True
        elif k is None:
            k = comp
            d[k] = {}
        elif not isinstance(d[k], dict):
            d[k] = {}
        d = d[k]
    return False


# ---------------------------------------------------------------- files
def slurp(path, binary=False):
    with open(path, 'rb') if binary else open(path, encoding='utf-8', errors='replace') as f:
        return f.read()


def steam_running(home):
    try:
        pid = int(slurp(os.path.join(home, '.steam', 'steam.pid')).strip())
        os.kill(pid, 0)
        return 'steam' in slurp(f'/proc/{pid}/comm')
    except (OSError, ValueError):
        return False


def write_atomic(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path) and not os.path.exists(path + BAK):
        with open(path, 'rb') as a, open(path + BAK, 'wb') as b:
            b.write(a.read())
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix='.steam-apply.')
    with os.fdopen(fd, 'wb') as w:
        w.write(data.encode() if isinstance(data, str) else data)
    os.replace(tmp, path)


def load_text(path):
    """A text KeyValues file as a dict: {} when it is missing, None when it does not parse - such a file is left
    alone rather than rewritten from whatever part of it could be read."""
    try:
        return vdf.loads(slurp(path))
    except FileNotFoundError:
        return {}
    except SyntaxError as e:
        print(f'steam-apply: not touching {path}, which does not parse: {e}', file=sys.stderr)
        return None


def apply_file(path, root_key, entries):
    """entries: [(path components, value or None)]. Missing files are created, unless there is only deleting to do."""
    if not os.path.exists(path) and all(v is None for _, v in entries):
        return False
    items = load_text(path)
    if items is None:
        return False
    k = find(items, root_key)
    if k is None or not isinstance(items[k], dict):
        k = k or root_key
        items[k] = {}
    changed = False
    for comps, value in entries:
        changed |= set_path(items[k], comps, value)
    if changed:
        write_atomic(path, vdf.dumps(items, pretty=True))
    return changed


def copy_if_changed(src, dst):
    data = slurp(src, binary=True)
    try:
        if slurp(dst, binary=True) == data:
            return False
    except FileNotFoundError:
        pass
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(dst), prefix='.steam-apply.')
    with os.fdopen(fd, 'wb') as f:
        f.write(data)
    os.replace(tmp, dst)
    return True


def split_path(path, appid):
    return [c for c in path.replace('<appid>', str(appid)).replace('\\', '/').split('/') if c]


# ---------------------------------------------------------------- shortcuts.vdf, binary KeyValues
def shortcut_appid(exe, name):
    """The app ID Steam gives a shortcut: a CRC of its Exe field (quotes included) and name, high bit set."""
    return (zlib.crc32(('"' + exe + '"' + name).encode()) & 0xFFFFFFFF) | 0x80000000


def i32(n):
    """`vdf` writes ints as signed 32-bit, and a shortcut's app ID has the high bit set."""
    return n - (1 << 32) if n >= 1 << 31 else n


def shortcut_entry(s, appid):
    return {
        'appid': i32(appid), 'AppName': s['appName'], 'Exe': '"' + s['exe'] + '"',
        'StartDir': '"' + (s.get('startDir') or os.path.dirname(s['exe'])) + '"',
        'icon': s.get('icon') or '', 'ShortcutPath': '', 'LaunchOptions': s.get('launchOptions') or '',
        'IsHidden': int(bool(s.get('hidden'))), 'AllowDesktopConfig': int(s.get('allowDesktopConfig', True)),
        'AllowOverlay': int(s.get('allowOverlay', True)), 'OpenVR': int(bool(s.get('openVR'))),
        'Devkit': 0, 'DevkitGameID': '', 'DevkitOverrideAppID': 0, 'LastPlayTime': 0, 'FlatpakAppID': '',
        'tags': {str(n): t for n, t in enumerate(s.get('tags') or [])},
    }


def appid_of(entry):
    k = find(entry, 'appid')
    return entry[k] & 0xFFFFFFFF if k is not None and isinstance(entry[k], int) else None


def apply_shortcuts(path, wanted, remove=()):
    """Upsert the shortcuts in `wanted` ([(appid, shortcut)]), matched by app ID, and drop the ones in `remove`
    (app IDs this tool created earlier that are no longer configured). Other shortcuts are kept."""
    try:
        before = slurp(path, binary=True)
    except FileNotFoundError:
        if not wanted:
            return False
        before = None
    try:
        items = vdf.binary_loads(before) if before else {}
    except SyntaxError as e:
        print(f'steam-apply: not touching {path}, which does not parse: {e}', file=sys.stderr)
        return False
    k = find(items, 'shortcuts')
    if k is None or not isinstance(items[k], dict):
        k = k or 'shortcuts'
        items[k] = {}
    remove = set(remove)
    entries = [e for e in items[k].values() if isinstance(e, dict) and appid_of(e) not in remove]
    for appid, s in wanted:
        new = shortcut_entry(s, appid)
        old = next((e for e in entries if appid_of(e) == appid), None)
        if old is None:
            entries.append(new)
            continue
        # play time is Steam's to keep
        played = find(old, 'LastPlayTime')
        if played is not None:
            new['LastPlayTime'] = old[played]
        old.clear()
        old.update(new)
    items[k] = {str(n): e for n, e in enumerate(entries)}
    data = vdf.binary_dumps(items)
    if data == before:
        return False
    write_atomic(path, data)
    return True


# ---------------------------------------------------------------- libraries / state
def library_paths(root):
    paths = [root]
    items = load_text(os.path.join(root, 'steamapps', 'libraryfolders.vdf')) or {}
    folders = items.get(find(items, 'libraryfolders'))
    for f in folders.values() if isinstance(folders, dict) else []:
        path = f.get(find(f, 'path')) if isinstance(f, dict) else None
        if isinstance(path, str) and path not in paths:
            paths.append(path)
    return paths


def load_state(root):
    try:
        st = json.loads(slurp(os.path.join(root, STATE)))
    except (FileNotFoundError, ValueError):
        st = {}
    if not isinstance(st, dict):
        st = {}
    st.setdefault('shortcuts', {})
    return st


def save_state(root, st):
    path = os.path.join(root, STATE)
    if not st['shortcuts']:
        if os.path.exists(path):
            os.remove(path)
        return
    text = json.dumps(st, sort_keys=True)
    try:
        if slurp(path) == text:
            return
    except FileNotFoundError:
        pass
    write_atomic(path, text)


def steam_root(home):
    link = os.path.join(home, '.steam', 'steam')
    return os.path.realpath(link) if os.path.exists(link) else os.path.join(home, '.local', 'share', 'Steam')


def with_installer(s, d):
    """Point an installer shortcut at its game inside the prefix at `d`, with the shim in front of `%command%`.
    The exe never changes, installed or not, so neither does the app ID."""
    shim = f"{quote(s['installer']['shim'])} {quote(d)} %command%"
    opts = s.get('launchOptions') or ''
    return {
        **s,
        'exe': os.path.join(d, 'pfx', s['installer']['game']),
        # Steam starts the process here, so it has to exist before the game does; the shim moves on to the
        # game's own directory
        'startDir': s.get('startDir') or d,
        'launchOptions': opts.replace('%command%', shim, 1) if '%command%' in opts else f'{shim} {opts}'.strip(),
    }


# ---------------------------------------------------------------- main
def apply(cfg, home):
    root = steam_root(home)
    apps = cfg.get('apps') or []
    for a in apps:
        s = a.get('shortcut')
        if s and s.get('installer'):
            d = os.path.join(root, 'steamapps', 'nonsteam', a['key'])
            os.makedirs(d, exist_ok=True)
            s = a['shortcut'] = with_installer(s, d)
        a['resolved'] = shortcut_appid(s['exe'], s['appName']) if s else a['appId']

    state = load_state(root)
    current = {a['key']: a['resolved'] for a in apps if a.get('shortcut')}
    stale = set(state['shortcuts'].values()) - set(current.values())

    by_file = {}
    for a in apps:
        for s in a.get('settings') or []:
            by_file.setdefault(s['file'], []).append((a['resolved'], split_path(s['path'], a['resolved']), s['value']))
    for aid in stale:
        by_file.setdefault('config', []).append((aid, ['Software', 'Valve', 'Steam', 'CompatToolMapping', str(aid)], None))

    log = []
    rel, root_key, _ = FILES['config']
    if by_file.get('config') and apply_file(os.path.join(root, rel), root_key, [(c, v) for _, c, v in by_file['config']]):
        log.append(rel)

    if by_file.get('appmanifest'):
        libs = library_paths(root)
        per_app = {}
        for aid, comps, v in by_file['appmanifest']:
            per_app.setdefault(aid, []).append((comps, v))
        for aid, entries in per_app.items():
            for lib in libs:
                mp = os.path.join(lib, 'steamapps', f'appmanifest_{aid}.acf')
                if os.path.exists(mp) and apply_file(mp, 'AppState', entries):
                    log.append(mp)

    udir = os.path.join(root, 'userdata')
    uids = sorted(d for d in os.listdir(udir) if d.isdigit() and d != '0') if os.path.isdir(udir) else []
    shortcuts = [(a['resolved'], a['shortcut']) for a in apps if a.get('shortcut')]
    for uid in uids:
        base = os.path.join(udir, uid)
        for name in ('localconfig', 'sharedconfig'):
            rel, root_key, _ = FILES[name]
            entries = [(c, v) for _, c, v in by_file.get(name, [])]
            if entries and apply_file(os.path.join(base, rel), root_key, entries):
                log.append(f'userdata/{uid}/{rel}')
        if (shortcuts or stale) and apply_shortcuts(os.path.join(base, 'config', 'shortcuts.vdf'), shortcuts, stale):
            log.append(f'userdata/{uid}/config/shortcuts.vdf')
        grid = os.path.join(base, 'config', 'grid')
        for a in apps:
            for kind, src in (a.get('artwork') or {}).items():
                if src:
                    fn = f"{a['resolved']}{GRID_SUFFIX[kind]}{os.path.splitext(src)[1] or '.png'}"
                    if copy_if_changed(src, os.path.join(grid, fn)):
                        log.append(f'userdata/{uid}/config/grid/{fn}')
        if stale and os.path.isdir(grid):
            stems = {f'{aid}{suffix}' for aid in stale for suffix in GRID_SUFFIX.values()}
            for fn in os.listdir(grid):
                if os.path.splitext(fn)[0] in stems:
                    os.remove(os.path.join(grid, fn))
                    log.append(f'userdata/{uid}/config/grid/{fn} (removed)')

    state['shortcuts'] = current
    save_state(root, state)
    return log


def main():
    home = os.environ['HOME']
    if steam_running(home):
        print('steam-apply: Steam is running, not touching config files', file=sys.stderr)
        return
    log = apply(json.loads(slurp(sys.argv[1])), home)
    if log:
        print('steam-apply: updated ' + ', '.join(log), file=sys.stderr)


if __name__ == '__main__':
    main()
