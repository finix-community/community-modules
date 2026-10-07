# finix compatibility suite
#
# discovers every test file next to a module - `modules/<kind>/<module>/tests/*.nix`
# - and exposes it as both an eval check and, where the file has a test script,
# a vm test.
#
# usage:
#   nix-build tests -A eval.xinetd.echo    # instantiate the closure only
#   nix-build tests -A vm.xinetd.echo      # boot it and run the script
#   nix-build tests -A registration        # every module has a test file
#   nix-build tests --arg finix /path/to/finix   # against another finix
#
# interactive:
#   nix-build tests -A vm.xinetd.echo.driverInteractive
#   ./result/bin/finix-test-driver
#
# `ci/run-suite.sh` walks `manifest` to build the compatibility table; see
# tests/README.md.
{
  finix ? (import ../lon.nix).finix,
  system ? builtins.currentSystem,
  pkgs ? null,
}:
let
  harness = import ./lib (
    {
      inherit finix system;
    }
    // (if pkgs == null then { } else { inherit pkgs; })
  );

  inherit (harness) lib;

  modulePaths = import ../modules;

  testsIn =
    modulePath:
    let
      dir = modulePath + "/tests";
    in
    if !builtins.pathExists dir then
      { }
    else
      lib.mapAttrs'
        (file: _: {
          name = lib.removeSuffix ".nix" file;
          value = import (dir + "/${file}");
        })
        (
          lib.filterAttrs (file: type: type == "regular" && lib.hasSuffix ".nix" file) (builtins.readDir dir)
        );

  # module -> test name -> test file contents
  discovered = lib.mapAttrs (_: testsIn) modulePaths;

  untested = lib.attrNames (lib.filterAttrs (_: tests: tests == { }) discovered);

  forEachTest =
    f:
    lib.mapAttrs (
      module: tests:
      lib.mapAttrs (test: contents: f "${module}.${test}" modulePaths.${module} contents) tests
    ) (lib.filterAttrs (_: tests: tests != { }) discovered);

  # what ci walks. kept flat and json-able on purpose.
  manifest = lib.concatLists (
    lib.mapAttrsToList (
      module: tests:
      lib.mapAttrsToList (test: contents: {
        inherit module test;
        kinds = [ "eval" ] ++ lib.optional (harness.hasVm contents) "vm";
        note = contents.note or "";
      }) tests
    ) (lib.filterAttrs (_: tests: tests != { }) discovered)
  );
in
{
  inherit manifest;

  eval = forEachTest harness.mkEvalCheck;

  vm = lib.filterAttrs (_: tests: tests != { }) (
    lib.mapAttrs (_: lib.filterAttrs (_: t: t != null)) (
      forEachTest (
        name: path: test:
        if harness.hasVm test then harness.mkVmTest name path test else null
      )
    )
  );

  # a module with no test file would silently vanish from the compatibility
  # table, which is worse than having no table - so this is a hard failure,
  # unlike a module that merely stopped working against finix.
  registration = harness.pkgs.runCommand "finix-compat-registration" { } (
    if untested == [ ] then
      "touch $out"
    else
      ''
        echo "these modules have no tests/ directory:" >&2
        ${lib.concatMapStringsSep "\n" (m: "echo '  - ${m}' >&2") untested}
        echo >&2
        echo "add modules/<kind>/<module>/tests/<name>.nix - see tests/README.md." >&2
        echo "a module that cannot be booted in a vm still needs an eval-only" >&2
        echo "test file with a 'note' saying why." >&2
        exit 1
      ''
  );

  # the same content as `manifest`, in a shape a shell loop can read without
  # needing a json parser: module<tab>test<tab>kind,kind
  manifestText = lib.concatMapStrings (
    e: "${e.module}\t${e.test}\t${lib.concatStringsSep "," e.kinds}\n"
  ) manifest;
}
