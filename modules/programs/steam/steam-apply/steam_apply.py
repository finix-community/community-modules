#!/usr/bin/env python3
"""Merge declarative per-app settings into Steam's config files.

steam-apply <apps.json>

Ported from nixos-steam's steam-config-apply (https://github.com/parzivale/nixos-steam).

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
* Files are written atomically; the first time a file is modified a `.steam-apply.bak` copy is kept.
* A shortcut whose app ID changed (new exe path or name), or that is no longer configured, is removed together
  with its compatibility tool mapping and artwork. Shortcuts added in Steam itself are never touched.
* Per-user files are written for every account under userdata/ that has logged in at least once.
* appmanifest settings only apply to installed games.
* A shortcut with an installer points at its game in a prefix of its own, steamapps/nonsteam/<key>/pfx, with the
  installer's shim in front of `%command%`. Removing it leaves that directory alone.
"""
import json, os, sys, tempfile, zlib
from shlex import quote

STATE = '.steam-apply-managed.json'
BAK = '.steam-apply.bak'
GRID_SUFFIX = {'grid': 'p', 'wide': '', 'hero': '_hero', 'logo': '_logo', 'icon': '_icon'}

# file -> (path relative to the Steam root or to userdata/<id>, root key, per user)
FILES = {
    'config': ('config/config.vdf', 'InstallConfigStore', False),
    'localconfig': ('config/localconfig.vdf', 'UserLocalConfigStore', True),
    'sharedconfig': ('7/remote/sharedconfig.vdf', 'UserRoamingConfigStore', True),
}


# ---------------------------------------------------------------- KeyValues text format
def tokenize(s):
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c in ' \t\r\n':
            i += 1
        elif s.startswith('//', i):
            j = s.find('\n', i)
            i = n if j < 0 else j + 1
        elif c in '{}':
            yield c
            i += 1
        elif c == '"':
            i += 1
            out = []
            while i < n and s[i] != '"':
                if s[i] == '\\' and i + 1 < n:
                    out.append({'n': '\n', 't': '\t', '\\': '\\', '"': '"'}.get(s[i + 1], '\\' + s[i + 1]))
                    i += 2
                else:
                    out.append(s[i])
                    i += 1
            i += 1
            yield ('s', ''.join(out))
        elif c == '[':  # conditional like [$WIN32]: ignore
            j = s.find(']', i)
            i = n if j < 0 else j + 1
        else:
            j = i
            while j < n and s[j] not in ' \t\r\n{}"':
                j += 1
            yield ('s', s[i:j])
            i = j


def parse(s):
    """Parse into nested lists of [key, value] pairs (value: str or list), preserving order and duplicates."""
    toks = list(tokenize(s))
    pos = 0

    def block():
        nonlocal pos
        items = []
        while pos < len(toks):
            t = toks[pos]
            if t == '}':
                pos += 1
                return items
            if t == '{':  # stray brace
                pos += 1
                continue
            key = t[1]
            pos += 1
            if pos >= len(toks):
                break
            v = toks[pos]
            if v == '{':
                pos += 1
                items.append([key, block()])
            elif v == '}':
                items.append([key, ''])
            else:
                pos += 1
                items.append([key, v[1]])
        return items

    return block()


def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\t', '\\t')


def dump(items, depth=0):
    out = []
    ind = '\t' * depth
    for k, v in items:
        if isinstance(v, list):
            out.append(f'{ind}"{esc(k)}"\n{ind}{{\n{dump(v, depth + 1)}{ind}}}\n')
        else:
            out.append(f'{ind}"{esc(k)}"\t\t"{esc(v)}"\n')
    return ''.join(out)


def set_path(items, path, value):
    """Set path to value (str); value None deletes the key (and its subtree) if present. Returns whether it changed."""
    for i, comp in enumerate(path):
        last = i == len(path) - 1
        hit = next((kv for kv in items if kv[0].lower() == comp.lower()), None)
        if value is None:
            if hit is None or (not last and not isinstance(hit[1], list)):
                return False
            if last:
                items.remove(hit)
                return True
        elif last:
            if hit is None:
                items.append([comp, value])
            elif hit[1] != value:
                hit[1] = value
            else:
                return False
            return True
        elif hit is None:
            hit = [comp, []]
            items.append(hit)
        elif not isinstance(hit[1], list):
            hit[1] = []
        items = hit[1]
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


def apply_file(path, root_key, entries):
    """entries: [(path components, value or None)]. Missing files are created, unless there is only deleting to do."""
    try:
        items = parse(slurp(path))
    except FileNotFoundError:
        if all(v is None for _, v in entries):
            return False
        items = []
    root = next((kv for kv in items if kv[0].lower() == root_key.lower() and isinstance(kv[1], list)), None)
    if root is None:
        root = [root_key, []]
        items.append(root)
    changed = False
    for comps, value in entries:
        changed |= set_path(root[1], comps, value)
    if changed:
        write_atomic(path, dump(items))
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


# ---------------------------------------------------------------- binary KeyValues (shortcuts.vdf)
def bkv_parse(b, i=0):
    """Parse a binary KeyValues map starting at i; returns (items, i) with items = [[key, value]]."""
    items = []
    while i < len(b):
        t = b[i]; i += 1
        if t == 0x08:
            return items, i
        e = b.index(b'\0', i); key = b[i:e].decode('utf-8', 'replace'); i = e + 1
        if t == 0x00:
            v, i = bkv_parse(b, i)
        elif t == 0x01:
            e = b.index(b'\0', i); v = b[i:e].decode('utf-8', 'replace'); i = e + 1
        elif t == 0x02:
            v = ('i32', int.from_bytes(b[i:i + 4], 'little', signed=True)); i += 4
        elif t == 0x07:
            v = ('u64', int.from_bytes(b[i:i + 8], 'little')); i += 8
        elif t == 0x03:
            v = ('f32', b[i:i + 4]); i += 4
        else:
            raise ValueError(f'unsupported binary KV type {t:#x}')
        items.append([key, v])
    return items, i


def bkv_dump(items):
    out = bytearray()
    for k, v in items:
        kb = k.encode() + b'\0'
        if isinstance(v, list):
            out += b'\x00' + kb + bkv_dump(v)
        elif isinstance(v, str):
            out += b'\x01' + kb + v.encode() + b'\0'
        elif v[0] == 'i32':
            out += b'\x02' + kb + (v[1] & 0xFFFFFFFF).to_bytes(4, 'little')
        elif v[0] == 'u64':
            out += b'\x07' + kb + v[1].to_bytes(8, 'little')
        elif v[0] == 'f32':
            out += b'\x03' + kb + v[1]
    return bytes(out + b'\x08')


def shortcut_appid(exe, name):
    """The app ID Steam gives a shortcut: a CRC of its Exe field (quotes included) and name, high bit set."""
    return (zlib.crc32(('"' + exe + '"' + name).encode()) & 0xFFFFFFFF) | 0x80000000


def shortcut_entry(s, appid):
    return [
        ['appid', ('i32', appid)], ['AppName', s['appName']], ['Exe', '"' + s['exe'] + '"'],
        ['StartDir', '"' + (s.get('startDir') or os.path.dirname(s['exe'])) + '"'],
        ['icon', s.get('icon') or ''], ['ShortcutPath', ''], ['LaunchOptions', s.get('launchOptions') or ''],
        ['IsHidden', ('i32', int(bool(s.get('hidden'))))],
        ['AllowDesktopConfig', ('i32', int(s.get('allowDesktopConfig', True)))],
        ['AllowOverlay', ('i32', int(s.get('allowOverlay', True)))], ['OpenVR', ('i32', int(bool(s.get('openVR'))))],
        ['Devkit', ('i32', 0)], ['DevkitGameID', ''], ['DevkitOverrideAppID', ('i32', 0)],
        ['LastPlayTime', ('i32', 0)], ['FlatpakAppID', ''],
        ['tags', [[str(n), t] for n, t in enumerate(s.get('tags') or [])]],
    ]


def apply_shortcuts(path, wanted, remove=()):
    """Upsert the shortcuts in `wanted` ([(appid, shortcut)]), matched by app ID, and drop the ones in `remove`
    (app IDs this tool created earlier that are no longer configured). Other shortcuts are kept."""
    try:
        items, _ = bkv_parse(slurp(path, binary=True))
    except FileNotFoundError:
        if not wanted:
            return False
        items = []
    root = next((kv for kv in items if kv[0].lower() == 'shortcuts' and isinstance(kv[1], list)), None)
    if root is None:
        root = ['shortcuts', []]
        items = [root]
    entries = [v for _, v in root[1] if isinstance(v, list)]

    def appid_of(e):
        return next((v[1] & 0xFFFFFFFF for k, v in e if k.lower() == 'appid' and isinstance(v, tuple)), None)

    remove = set(remove)
    entries = [e for e in entries if appid_of(e) not in remove]
    for appid, s in wanted:
        new = shortcut_entry(s, appid)
        old = next((e for e in entries if appid_of(e) == appid), None)
        if old is None:
            entries.append(new)
            continue
        # play time is Steam's to keep
        played = next((v for k, v in old if k.lower() == 'lastplaytime'), None)
        if played is not None:
            for kv in new:
                if kv[0] == 'LastPlayTime':
                    kv[1] = played
        old[:] = new
    root[1] = [[str(n), e] for n, e in enumerate(entries)]
    data = bkv_dump(items)
    try:
        if slurp(path, binary=True) == data:
            return False
    except FileNotFoundError:
        pass
    write_atomic(path, data)
    return True


# ---------------------------------------------------------------- libraries / state
def library_paths(root):
    paths = [root]
    try:
        items = parse(slurp(os.path.join(root, 'steamapps', 'libraryfolders.vdf')))
    except FileNotFoundError:
        return paths
    for k, v in items:
        if k.lower() == 'libraryfolders' and isinstance(v, list):
            for _, f in v:
                if isinstance(f, list):
                    for fk, fv in f:
                        if fk.lower() == 'path' and isinstance(fv, str) and fv not in paths:
                            paths.append(fv)
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
