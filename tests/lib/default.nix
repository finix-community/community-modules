# harness for the finix compatibility suite
#
# tests live next to the module they cover, one file per test:
#
#   modules/services/xinetd/tests/echo.nix
#
# a test file is an attrset:
#
#   {
#     machine = { pkgs, ... }: { services.xinetd.enable = true; };  # or `nodes`
#     testScript = '' ... '';                # optional
#     replacesFinixModules = [ ... ];        # optional
#     note = "...";                          # optional
#   }
#
# each file is checked against a finix revision at up to two depths:
#
#   eval - the host is imported into an otherwise minimal finix system and the
#          system closure is instantiated. this is what catches option renames
#          and api drift in finix, which is how these modules usually break.
#          every test file gets one.
#
#   vm   - the same host is booted under qemu and `testScript` runs against it.
#          only files that have a `testScript` get one; the rest are eval-only
#          and say so in COMPATIBILITY.md, with their `note` as the reason.
#
# the vm side is finix's own test driver, so `machine`/`nodes`/`testScript`
# behave exactly as they do in finix's `tests/`.
{
  # the finix checkout to test against. defaults to the pin in lon.lock; ci
  # overrides it with a fresh clone of finix main, which is what makes the
  # compatibility table move.
  finix ? (import ../../lon.nix).finix,

  system ? builtins.currentSystem,

  # packages come from the nixpkgs *finix* pins, not ours. the table answers
  # "does this module work at finix rev X", so the answer should depend on the
  # finix commit alone - pinning nixpkgs separately would let our own bumps
  # move the results.
  pkgs ? import (import (finix + "/lon.nix")).nixpkgs {
    inherit system;
    # steam, v2rayn and friends are unfree; a compatibility check that skips
    # them is not much of a compatibility check.
    config.allowUnfree = true;
  },
}:
let
  inherit (pkgs) lib;

  finixTests = import (finix + "/tests/lib") { inherit pkgs lib; };

  # finix's test driver imports every finix module into each node. a few of our
  # modules are alternative implementations of a module finix also ships
  # (pipewire, wireplumber), and declaring the same option twice is an eval
  # error - so those tests name the finix modules they replace.
  disableFinix = test: {
    disabledModules = map (p: finix + "/modules/${p}") (test.replacesFinixModules or [ ]);
  };

  nodesOf = test: if test ? nodes then test.nodes else { machine = test.machine; };

  # what gets imported into every node, and into the eval check: the module
  # under test and whatever the test file says it takes to turn it on. nothing
  # else - a test file that needs a device manager picks one itself, the same
  # way finix's own tests do, because some of these modules pick for you.
  hostFor = modulePath: test: node: {
    imports = [
      (disableFinix test)
      modulePath
      node
    ];
  };

  # the smallest host finix will evaluate. anything else a module needs belongs
  # in its test file, where it is visible.
  minimalHost = {
    nixpkgs.pkgs = pkgs;
    networking.hostName = "compat";
    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };
  };
in
{
  inherit pkgs lib finix;

  hasVm = test: test ? testScript;

  # forcing `drvPath` evaluates the whole system - assertions included, since
  # finix routes `system.topLevel` through `checkAssertWarn`. the string
  # context is discarded so this instantiates the closure without building it.
  mkEvalCheck =
    name: modulePath: test:
    let
      # `nodes` is tied back in the way finix's own driver does it, so a
      # multi-node test that reads another node's config still evaluates here.
      systems = lib.mapAttrs (
        _: node:
        (import finix).lib.finixSystem {
          inherit lib;
          specialArgs = {
            nodes = systems;
          };
          modules = [
            minimalHost
            (hostFor modulePath test node)
          ];
        }
      ) (nodesOf test);
    in
    pkgs.runCommand "finix-compat-eval-${name}" { } (
      lib.concatMapStringsSep "\n" (
        system: "echo ${builtins.unsafeDiscardStringContext system.config.system.topLevel.drvPath} >> $out"
      ) (lib.attrValues systems)
    );

  mkVmTest =
    name: modulePath: test:
    finixTests.mkTest (
      (removeAttrs test [
        "machine"
        "note"
        "replacesFinixModules"
      ])
      // {
        name = "finix-compat-${name}";
        nodes = lib.mapAttrs (_: hostFor modulePath test) (nodesOf test);
      }
    );
}
