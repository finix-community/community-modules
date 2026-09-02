# expanded option set for finix' `services.nftables`.
#
# finix ships a minimal `services.nftables` that only knows how to load a set
# of structured `tables`. this module overlays the richer surface that used to
# live in finix proper:
#
#   - raw `ruleset` / `rulesetFile` config, concatenated onto the generated file
#   - `flushRuleset` / `extraDeletions` cleanup control
#   - `allowPing`, which re-opens ICMP echo on the `providers.firewall` table
#
# it works purely by overriding options finix already exposes
# (`configFile`, the nftables finit task and the `finix-fw` table), so it must
# be imported *alongside* finix' nftables module, not on its own.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.nftables;
  fwCfg = config.providers.firewall;

  enabledTables = lib.filterAttrs (_: table: table.enable) cfg.tables;

  # superset of finix' tables-only deletions that also honours flushRuleset and
  # extraDeletions.
  deletions = ''
    ${
      if cfg.flushRuleset then
        "flush ruleset"
      else
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (_: table: ''
            table ${table.family} ${table.name}
            delete table ${table.family} ${table.name}
          '') enabledTables
        )
    }
    ${cfg.extraDeletions}
  '';

  deletionsFile = pkgs.writeText "nftables-deletions.nft" deletions;

  # a regenerated config file that appends `ruleset` / `rulesetFile` and uses the
  # deletions above. mirrors finix' generation so behaviour is identical when no
  # extra source is set.
  configFile = pkgs.writeTextFile {
    name = "nftables.conf";
    text = ''
      ${deletions}
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (_: table: ''
          table ${table.family} ${table.name} {
            ${table.content}
          }
        '') enabledTables
      )}
      ${cfg.ruleset}
      ${
        if cfg.rulesetFile != null then
          if cfg.flattenRulesetFile then
            builtins.readFile cfg.rulesetFile
          else
            ''
              include "${cfg.rulesetFile}"
            ''
        else
          ""
      }
    '';
    checkPhase = lib.optionalString cfg.checkRuleset ''
      cp $out ruleset.conf
      ${cfg.preCheckRuleset}
      export NIX_REDIRECTS=${
        lib.escapeShellArg (
          lib.concatStringsSep ":" (lib.mapAttrsToList (n: v: "${n}=${v}") cfg.checkRulesetRedirects)
        )
      }
      LD_PRELOAD="${pkgs.buildPackages.libredirect}/lib/libredirect.so ${pkgs.buildPackages.lklWithFirewall.lib}/lib/liblkl-hijack.so" \
        ${pkgs.buildPackages.nftables}/bin/nft --check --file ruleset.conf
    '';
  };

  # only take over the generated config / teardown when one of the extra config
  # sources is actually in use; otherwise leave finix' minimal generation alone.
  extraConfig = cfg.ruleset != "" || cfg.rulesetFile != null || cfg.flushRuleset || cfg.extraDeletions != "";

  # `finix-fw` rendering, mirroring finix' nftables backend but re-adding the
  # allowPing rule.
  portsToNftSet =
    ports: portRanges:
    lib.concatStringsSep ", " (
      map toString ports ++ map ({ from, to }: "${toString from}-${toString to}") portRanges
    );

  ifaceSet = lib.concatStringsSep ", " (map (x: ''"${x}"'') cfg.trustedInterfaces);

  tcpSet = portsToNftSet fwCfg.allowedTCPPorts fwCfg.allowedTCPPortRanges;
  udpSet = portsToNftSet fwCfg.allowedUDPPorts fwCfg.allowedUDPPortRanges;

  firewallActive = fwCfg.enable && fwCfg.backend == "nftables";
in
{
  options.services.nftables = {
    allowPing = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether the {option}`providers.firewall` implementation responds
        to incoming ICMPv4 echo requests ("pings").
      '';
    };

    flushRuleset = lib.mkEnableOption "flushing the entire ruleset on each start";

    extraDeletions = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        # this makes deleting a non-existing table a no-op instead of an error
        table inet some-table;

        delete table inet some-table;
      '';
      description = ''
        Extra deletion commands to be run on every firewall start and
        after stopping the firewall.
      '';
    };

    ruleset = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        table inet filter {
          chain input {
            type filter hook input priority filter; policy drop;
            tcp dport 22 accept
          }
        }
      '';
      description = ''
        The ruleset to be used with nftables. Should be in a format that
        can be loaded using "/bin/nft -f". Definitions from multiple modules
        are concatenated, allowing rules to be contributed without
        overwriting each other. Note that if the tables should be cleaned
        first, either:
        - services.nftables.flushRuleset = true; needs to be set (flushes all tables)
        - services.nftables.extraDeletions needs to be set
        - or services.nftables.tables can be used, which will clean up the table automatically
      '';
    };

    rulesetFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The ruleset file to be used with nftables. Should be in a format that
        can be loaded using "nft -f".
      '';
    };

    flattenRulesetFile = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Use `builtins.readFile` rather than `include` to handle {option}`rulesetFile`.
        It is useful when you want to apply {option}`preCheckRuleset` to
        {option}`rulesetFile`.

        ::: {.note}
        It is expected that {option}`rulesetFile` can be accessed from the build sandbox.
        :::
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf extraConfig {
      # finix exposes `configFile` with a low-priority (mkOptionDefault) default,
      # so mkDefault is enough to take over generation while still yielding to a
      # configFile the user set explicitly.
      services.nftables.configFile = lib.mkDefault configFile;

      finit.tasks.nftables.post = lib.mkForce (pkgs.writeShellScript "nftables.sh" ''
        ${lib.getExe cfg.package} -f ${deletionsFile}
      '');
    })

    (lib.mkIf firewallActive {
      services.nftables.tables.finix-fw.content = lib.mkForce ''
        chain input {
          type filter hook input priority filter; policy drop;

          ${lib.optionalString (
            ifaceSet != ""
          ) ''iifname { ${ifaceSet} } accept comment "trusted interfaces"''}

          ct state vmap {
            invalid : drop,
            established : accept,
            related : accept,
            new : jump input-allow,
            untracked : jump input-allow,
          }

          ${lib.optionalString fwCfg.rejectPackets ''
            meta l4proto tcp reject with tcp reset
            reject
          ''}
        }

        chain input-allow {
          ${lib.optionalString (tcpSet != "") "tcp dport { ${tcpSet} } accept"}
          ${lib.optionalString (udpSet != "") "udp dport { ${udpSet} } accept"}

          ${lib.optionalString cfg.allowPing ''
            icmp type echo-request accept comment "allow ping"
            icmpv6 type echo-request accept comment "allow ping6"
          ''}
        }
      '';
    })
  ]);
}
