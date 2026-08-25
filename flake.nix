{
  description = "community maintained modules for finix - experimental, niche, and fast-moving modules live here";

  outputs =
    { self }:
    let
      sources = import ./lon.nix;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      # the compatibility suite builds finix systems, so it only means anything
      # where one can be built
      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forSystems =
        fn:
        builtins.listToAttrs (
          map (system: {
            name = system;
            value = fn system;
          }) systems
        );

      pkgsFor = system: import sources.nixpkgs { inherit system; };
    in
    {
      formatter = forSystems (system: (pkgsFor system).nixfmt-tree);

      nixosModules = import ./modules;

      hjemModules = import ./hjem;

      # the suite in tests/, against the finix pinned in lon.lock. this is the
      # gate that goes red on a commit here; the compatibility table in
      # COMPATIBILITY.md runs the same tests against finix main and only
      # reports. see tests/README.md.
      checks = builtins.listToAttrs (
        map (system: {
          name = system;
          value =
            let
              lib = (pkgsFor system).lib;

              suite = import ./tests { inherit system; };

              flatten =
                kind:
                lib.concatMapAttrs (
                  module: tests:
                  lib.mapAttrs' (test: check: lib.nameValuePair "${kind}-${module}-${test}" check) tests
                ) suite.${kind};
            in
            flatten "eval" // flatten "vm" // { inherit (suite) registration; };
        }) linuxSystems
      );
    };
}
