# tests

every module in this repository is checked against `finix`, and the result ends
up in [COMPATIBILITY.md](../COMPATIBILITY.md): per module, the last `finix`
commit it was known to work with.

tests live **next to the module they cover**, one file per test:

```
modules/services/xinetd/tests/echo.nix
modules/programs/steam/tests/eval.nix
```

## writing one

a test file is an attrset:

```nix
{
  # the host configuration under test. an attrset, or a function taking the
  # usual module arguments - `modules` is finix's module set, for pulling in
  # finix modules that are not part of its base system.
  machine =
    { pkgs, ... }:
    {
      services.mdevd.enable = true;
      services.xinetd.enable = true;
    };

  # optional. with a test script the module is booted under qemu; without one
  # the test is eval-only.
  testScript = ''
    machine.start()
    machine.wait_for_console_text("entering runlevel 2")
    machine.wait_until_succeeds("pgrep -x xinetd")
    machine.shutdown()
  '';

  # optional, and expected on eval-only tests: why there is no vm test. it is
  # quoted in COMPATIBILITY.md.
  note = "needs a gpu and a seat";

  # optional. finix modules this one reimplements, so their options are not
  # declared twice.
  replacesFinixModules = [ "programs/pipewire" ];
}
```

`machine`, `nodes` and `testScript` behave exactly as they do in finix's own
`tests/`, because the vm half *is* finix's test driver. use `nodes` instead of
`machine` for a multi-node test.

each file is checked at up to two depths:

- **eval** - the host is imported into an otherwise minimal finix system and
  its closure is instantiated, assertions included. every test file gets this.
  it is cheap and it catches the option renames and api drift that break these
  modules in practice.
- **vm** - the same host is booted under qemu and `testScript` runs against it.
  only files with a `testScript`.

a module with no `tests/` directory fails `nix-build tests -A registration`, so
nothing can quietly drop off the table. a module that genuinely cannot be
booted in ci still needs an eval-only file with a `note` saying why.

## running them

```sh
nix-build tests -A eval.xinetd.echo     # instantiate only
nix-build tests -A vm.xinetd.echo       # boot it (needs kvm)
nix-build tests -A registration         # every module has a test
nix flake check                         # everything, against the pinned finix
```

interactively:

```sh
nix-build tests -A vm.xinetd.echo.driverInteractive
./result/bin/finix-test-driver
```

against a finix checkout of your own:

```sh
nix-build tests -A eval.xinetd.echo --arg finix /path/to/finix
```

packages come from the nixpkgs *finix* pins, not the one in this repository's
`lon.lock`. the table answers "does this module work at finix rev X", so the
answer should not move when we bump our own nixpkgs.

## the compatibility table

`ci/run-suite.sh` runs everything against a finix checkout and writes raw
results; `ci/report.nix` merges them into `ci/compat-state.json` and renders
`COMPATIBILITY.md`. the state file is what lets a broken module keep pointing
at the last commit it worked with, which the current run cannot know by itself.

```sh
FINIX=/path/to/finix ci/run-suite.sh      # KINDS=eval to skip the vm half
```

`.github/workflows/finix-compat.yml` does this on every push, and daily, against
finix `main`. a module failing there is recorded, not fatal - that is the point
of the table. `nix flake check` in `ci.yml` is the gate that goes red, and it
runs against the finix pinned in `lon.lock`.
