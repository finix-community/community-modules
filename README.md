# community-modules

- community maintained modules for `finix`
- a place for experimentation, niche integrations, opinionated modules, and rapidly evolving ideas
- provide an ecosystem similar in spirit to the Arch User Repository (AUR), but for `finix` modules

---

# expectations

modules in this repository:

- may change rapidly
- may have varying quality levels
- may be minimally maintained
- may not follow all `finix` best practices yet
- may become unmaintained over time

this repository prioritizes:

- experimentation
- collaboration
- ecosystem growth
- low contribution friction

because of that, [COMPATIBILITY.md](COMPATIBILITY.md) records, per module, the
last `finix` commit it was known to work with. it is regenerated on every push
and daily against `finix` `main`. check it before reaching for a module, and
see [tests/README.md](tests/README.md) to add a test for one.

# usage (flake-based)

to use this repository, add the following to your flake inputs:

```
{
  inputs = {
    # other inputs...
    community-modules.url = "github:finix-community/community-modules";
  }
}
```

then, add the following to your outputs:

```
  outputs =
    inputs@{
      self,
      nixpkgs,
      finix,
      community-modules, # <- NEW
      ...
    }:
    {
      nixosConfigurations.your-system = finix.lib.finixSystem {
        # ...

        modules = with inputs.community-modules.nixosModules; [
          pipewire
          v2rayn
          amnezia-vpn
          # other modules
        ];

        # ...
      };
```

# future plans

as this component of `finix` matures, and more modules are added, we will eventually create a `stable` branch which only contains modules that are confirmed to be working and battle tested by the maintainers. when this happens, the `main` branch will be what is used for rapid and breaking changes that may or may not contain untested nix code. while we do try and review as many modules as we can, not all maintainers have the exact use cases that these modules were designed for, so we will have limited field testing on them.

with that being said, if there is something you think is missing from `finix` that you would like to see ported from `NixOS`, or something from any other OS that is not present in either `finix` nor `NixOS`, feel free to open a PR and add it here!
