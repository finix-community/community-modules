import os, tempfile, unittest

import steam_apply as sa


class Env:
    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        self.root = os.path.join(self.home, '.local', 'share', 'Steam')
        os.makedirs(os.path.join(self.root, 'userdata', '123', 'config'))

    def path(self, rel):
        return os.path.join(self.root, rel)

    def read(self, rel, binary=False):
        with open(self.path(rel), 'rb' if binary else 'r') as f:
            return f.read()

    def write(self, rel, data):
        os.makedirs(os.path.dirname(self.path(rel)), exist_ok=True)
        with open(self.path(rel), 'wb' if isinstance(data, bytes) else 'w') as f:
            f.write(data)

    def run(self, apps):
        return sa.apply({'apps': apps}, self.home)

    def shortcuts(self):
        items, _ = sa.bkv_parse(self.read('userdata/123/config/shortcuts.vdf', binary=True))
        return [dict(e) for _, e in items[0][1]]


def shortcut(key, exe, **kw):
    return {'key': key, 'appId': None, 'settings': kw.pop('settings', []), 'artwork': kw.pop('artwork', {}),
            'shortcut': {'appName': kw.pop('appName', key), 'exe': exe, **kw}}


def compat(tool):
    base = 'Software/Valve/Steam/CompatToolMapping/<appid>/'
    return [{'file': 'config', 'path': base + 'name', 'value': tool},
            {'file': 'config', 'path': base + 'config', 'value': ''},
            {'file': 'config', 'path': base + 'priority', 'value': '250'}]


class Text(unittest.TestCase):
    def test_roundtrip(self):
        text = '"a"\n{\n\t"b"\t\t"c \\"q\\""\n\t"d"\n\t{\n\t}\n}\n'
        self.assertEqual(sa.dump(sa.parse(text)), text)

    def test_set_path_keeps_spelling_and_deletes(self):
        items = sa.parse('"Root" { "Apps" { "570" { "x" "1" } } }')
        self.assertTrue(sa.set_path(items, ['root', 'apps', '570', 'y'], '2'))
        self.assertFalse(sa.set_path(items, ['root', 'apps', '570', 'y'], '2'))
        self.assertIn('"Apps"', sa.dump(items))
        self.assertTrue(sa.set_path(items, ['root', 'apps', '570'], None))
        self.assertFalse(sa.set_path(items, ['root', 'apps', '570'], None))


class SteamApps(unittest.TestCase):
    def test_settings_land_in_their_files(self):
        e = Env()
        e.write('userdata/123/config/localconfig.vdf', '"UserLocalConfigStore"\n{\n\t"friends"\t\t"keep"\n}\n')
        e.write('steamapps/appmanifest_570.acf', '"AppState"\n{\n\t"appid"\t\t"570"\n\t"AutoUpdateBehavior"\t\t"0"\n}\n')
        dota = {'key': 'dota', 'appId': 570, 'shortcut': None, 'artwork': {}, 'settings': [
            {'file': 'localconfig', 'path': 'Software/Valve/Steam/apps/<appid>/LaunchOptions', 'value': '-novid %command%'},
            {'file': 'sharedconfig', 'path': 'Software/Valve/Steam/apps/<appid>/cloudenabled', 'value': '0'},
            {'file': 'appmanifest', 'path': 'AutoUpdateBehavior', 'value': '1'},
            {'file': 'appmanifest', 'path': 'Unused', 'value': 'x'},
        ] + compat('proton_9')}
        # not installed: its manifest is left alone rather than created
        ghost = {'key': 'ghost', 'appId': 999, 'shortcut': None, 'artwork': {},
                 'settings': [{'file': 'appmanifest', 'path': 'AutoUpdateBehavior', 'value': '1'}]}
        e.run([dota, ghost])
        local = e.read('userdata/123/config/localconfig.vdf')
        self.assertIn('"friends"\t\t"keep"', local)
        self.assertIn('"LaunchOptions"\t\t"-novid %command%"', local)
        self.assertIn('"cloudenabled"\t\t"0"', e.read('userdata/123/7/remote/sharedconfig.vdf'))
        self.assertIn('"AutoUpdateBehavior"\t\t"1"', e.read('steamapps/appmanifest_570.acf'))
        self.assertFalse(os.path.exists(e.path('steamapps/appmanifest_999.acf')))
        self.assertIn('"570"', e.read('config/config.vdf'))
        self.assertTrue(os.path.exists(e.path('userdata/123/config/localconfig.vdf' + sa.BAK)))
        self.assertEqual(e.run([dota, ghost]), [])  # idempotent


class Shortcuts(unittest.TestCase):
    def test_appid(self):
        aid = sa.shortcut_appid('/opt/game/run', 'Game')
        self.assertEqual(aid, (__import__('zlib').crc32(b'"/opt/game/run"Game') & 0xFFFFFFFF) | 0x80000000)
        self.assertTrue(aid & 0x80000000)

    def test_roundtrip_and_upsert(self):
        e = Env()
        existing = sa.bkv_dump([['shortcuts', [['0', [['appid', ('i32', 5)], ['AppName', 'Mine'], ['Exe', '"/bin/x"'],
                                                    ['LastPlayTime', ('i32', 7)], ['tags', []]]]]]])
        self.assertEqual(sa.bkv_dump(sa.bkv_parse(existing)[0]), existing)
        e.write('userdata/123/config/shortcuts.vdf', existing)
        apps = [shortcut('game', '/opt/game/run', appName='Game', launchOptions='-x', tags=['nix'])]
        e.run(apps)
        en = e.shortcuts()
        self.assertEqual([x['AppName'] for x in en], ['Mine', 'Game'])
        self.assertEqual(en[1]['appid'][1] & 0xFFFFFFFF, sa.shortcut_appid('/opt/game/run', 'Game'))
        self.assertEqual(en[1]['StartDir'], '"/opt/game"')
        self.assertEqual(en[1]['LaunchOptions'], '-x')
        self.assertEqual(e.run(apps), [])  # idempotent

    def test_play_time_is_kept(self):
        e = Env()
        apps = [shortcut('game', '/opt/game/run')]
        e.run(apps)
        aid = sa.shortcut_appid('/opt/game/run', 'game')
        items, _ = sa.bkv_parse(e.read('userdata/123/config/shortcuts.vdf', binary=True))
        for kv in items[0][1][0][1]:
            if kv[0] == 'LastPlayTime':
                kv[1] = ('i32', 1234)
        e.write('userdata/123/config/shortcuts.vdf', sa.bkv_dump(items))
        e.run([shortcut('game', '/opt/game/run', launchOptions='-y')])
        en = e.shortcuts()[0]
        self.assertEqual(en['LastPlayTime'], ('i32', 1234))
        self.assertEqual(en['LaunchOptions'], '-y')
        self.assertEqual(en['appid'][1] & 0xFFFFFFFF, aid)

    def test_path_change_replaces_and_cleans_up(self):
        e = Env()
        art = os.path.join(e.home, 'hero.jpg')
        with open(art, 'wb') as f:
            f.write(b'img')

        def apps(exe):
            return [shortcut('ra', exe, appName='RetroArch', settings=compat('proton_9'), artwork={'hero': art, 'grid': None})]

        e.run(apps('/nix/store/aaa-retroarch/bin/retroarch'))
        old = sa.shortcut_appid('/nix/store/aaa-retroarch/bin/retroarch', 'RetroArch')
        grid = e.path('userdata/123/config/grid')
        self.assertTrue(os.path.exists(os.path.join(grid, f'{old}_hero.jpg')))
        self.assertIn(f'"{old}"', e.read('config/config.vdf'))
        # the store path changes on update: the entry is replaced, not duplicated
        e.run(apps('/nix/store/bbb-retroarch/bin/retroarch'))
        new = sa.shortcut_appid('/nix/store/bbb-retroarch/bin/retroarch', 'RetroArch')
        self.assertEqual([x['appid'][1] & 0xFFFFFFFF for x in e.shortcuts()], [new])
        self.assertFalse(os.path.exists(os.path.join(grid, f'{old}_hero.jpg')))
        self.assertTrue(os.path.exists(os.path.join(grid, f'{new}_hero.jpg')))
        conf = e.read('config/config.vdf')
        self.assertNotIn(f'"{old}"', conf)
        self.assertIn(f'"{new}"', conf)
        # removed from the config: entry, mapping and artwork go away
        e.run([])
        self.assertEqual(e.shortcuts(), [])
        self.assertFalse(os.path.exists(os.path.join(grid, f'{new}_hero.jpg')))
        self.assertNotIn(f'"{new}"', e.read('config/config.vdf'))
        self.assertFalse(os.path.exists(e.path(sa.STATE)))

    def test_nothing_configured_creates_nothing(self):
        e = Env()
        self.assertEqual(e.run([]), [])
        self.assertFalse(os.path.exists(e.path('userdata/123/config/shortcuts.vdf')))
        self.assertFalse(os.path.exists(e.path('config/config.vdf')))


class Installer(unittest.TestCase):
    GAME = 'drive_c/Program Files/Game/game.exe'

    def app(self, shim='/nix/store/aaa-steam-install-g', **kw):
        return shortcut('g', None, appName='Game', installer={'shim': shim, 'game': self.GAME},
                        settings=compat('GE-Proton'), **kw)

    def test_points_at_the_game_in_its_own_prefix(self):
        e = Env()
        e.run([self.app()])
        d = e.path('steamapps/nonsteam/g')
        exe = os.path.join(d, 'pfx', self.GAME)
        en = e.shortcuts()[0]
        self.assertEqual(en['Exe'], f'"{exe}"')
        self.assertEqual(en['StartDir'], f'"{d}"')
        self.assertTrue(os.path.isdir(d))
        self.assertEqual(en['LaunchOptions'], f'/nix/store/aaa-steam-install-g {d} %command%')
        self.assertEqual(en['appid'][1] & 0xFFFFFFFF, sa.shortcut_appid(exe, 'Game'))
        self.assertIn(f'"{sa.shortcut_appid(exe, "Game")}"', e.read('config/config.vdf'))

    def test_shim_goes_in_front_of_command(self):
        e = Env()
        e.run([self.app(launchOptions='gamemoderun %command% -dx11')])
        d = e.path('steamapps/nonsteam/g')
        self.assertEqual(e.shortcuts()[0]['LaunchOptions'], f'gamemoderun /nix/store/aaa-steam-install-g {d} %command% -dx11')
        e.run([self.app(launchOptions='-dx11')])
        self.assertEqual(e.shortcuts()[0]['LaunchOptions'], f'/nix/store/aaa-steam-install-g {d} %command% -dx11')

    def test_new_shim_keeps_the_app_id(self):
        e = Env()
        e.run([self.app()])
        before = e.shortcuts()[0]['appid']
        e.run([self.app(shim='/nix/store/bbb-steam-install-g')])
        en = e.shortcuts()
        self.assertEqual([x['appid'] for x in en], [before])
        self.assertTrue(en[0]['LaunchOptions'].startswith('/nix/store/bbb-steam-install-g '))

    def test_removing_keeps_the_install(self):
        e = Env()
        e.run([self.app()])
        e.write(os.path.join('steamapps/nonsteam/g/pfx', self.GAME), b'MZ')
        e.run([])
        self.assertEqual(e.shortcuts(), [])
        self.assertTrue(os.path.exists(e.path(os.path.join('steamapps/nonsteam/g/pfx', self.GAME))))


if __name__ == '__main__':
    unittest.main()
