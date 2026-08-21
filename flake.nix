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
    };
}
