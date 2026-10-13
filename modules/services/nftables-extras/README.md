# nftables-extras

Expanded option set for finix' `services.nftables`.

finix core ships a deliberately minimal `services.nftables` that only loads a
set of structured `tables`. This module overlays the richer surface that used
to live in finix proper, without adding any hooks back to core:

- `services.nftables.ruleset` / `rulesetFile` / `flattenRulesetFile` — raw
  nftables config concatenated onto the generated ruleset.
- `services.nftables.flushRuleset` / `extraDeletions` — control over the
  cleanup commands run on start and teardown.
- `services.nftables.allowPing` — re-opens ICMPv4/6 echo on the
  `providers.firewall` (`finix-fw`) table. finix' base firewall drops ping by
  default; import this module to make it configurable again.

It only sets values on options finix already exposes (`configFile`, the
nftables finit task, and the `finix-fw` table), so it must be imported
**alongside** finix' `services.nftables` module — it does nothing on its own.
