#!/usr/bin/env bash
#
# runs the compatibility suite against a finix checkout and writes the raw
# results that ci/report.nix turns into COMPATIBILITY.md.
#
#   FINIX=/path/to/finix ci/run-suite.sh
#
# a module that fails is recorded, not fatal: the table exists precisely to say
# which modules have fallen behind finix. only the harness itself failing -
# discovery, the registration check - stops the run.

set -uo pipefail

: "${FINIX:?set FINIX to a finix checkout}"

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out=${OUT:-$root/.ci/run}
system=${SYSTEM:-$(nix-instantiate --eval --expr 'builtins.currentSystem' | tr -d '"')}

nix_args=(tests --arg finix "$FINIX" --argstr system "$system")

mkdir -p "$out/logs"

echo "==> finix:  $FINIX"
echo "==> system: $system"

echo "==> checking every module has a test"
if ! nix-build "${nix_args[@]}" -A registration --no-out-link > "$out/logs/registration.log" 2>&1; then
  cat "$out/logs/registration.log" >&2
  exit 1
fi

echo "==> collecting tests"
if ! nix-instantiate --eval --raw "${nix_args[@]}" -A manifestText > "$out/manifest.txt" 2>"$out/logs/manifest.log"; then
  cat "$out/logs/manifest.log" >&2
  exit 1
fi
nix-instantiate --eval --strict --json "${nix_args[@]}" -A manifest > "$out/manifest.json"

# results.json holds nothing but identifiers and booleans, so building it by
# hand here is safe; anything with prose in it (the eval-only notes) is read
# from manifest.json by the report instead.
results=$out/results.json
printf '{\n  "system": "%s",\n  "results": [\n' "$system" > "$results"
first=1
failed=0

while IFS=$'\t' read -r module test kinds; do
  [ -n "$module" ] || continue
  for kind in ${kinds//,/ }; do
    # KINDS=eval skips the vm half, which is what you want when iterating
    # locally or on a machine without kvm
    if [ -n "${KINDS:-}" ] && [[ ",${KINDS}," != *",$kind,"* ]]; then
      continue
    fi

    attr="$kind.$module.$test"
    log="$out/logs/$kind-$module-$test.log"
    printf '  %-4s %-16s %-18s ' "$kind" "$module" "$test"

    if nix-build "${nix_args[@]}" -A "$attr" --no-out-link > "$log" 2>&1; then
      ok=true
      echo "ok"
    elif [ "$kind" = vm ] && grep -q "Timeout waiting for mount-nix-store" "$log"; then
      # the vm never got its 9p store mount and so never booted. that is the
      # host being slow, not the module being broken, and recording it as
      # broken would move the module's last-good commit for no reason.
      echo -n "retrying (vm did not boot) ... "
      if nix-build "${nix_args[@]}" -A "$attr" --no-out-link > "$log" 2>&1; then
        ok=true
        echo "ok"
      else
        ok=false
        failed=$((failed + 1))
        echo "FAILED (see ${log#"$root"/})"
      fi
    else
      ok=false
      failed=$((failed + 1))
      echo "FAILED (see ${log#"$root"/})"
    fi

    [ $first -eq 1 ] || printf ',\n' >> "$results"
    first=0
    printf '    {"module": "%s", "test": "%s", "kind": "%s", "ok": %s}' \
      "$module" "$test" "$kind" "$ok" >> "$results"
  done
done < "$out/manifest.txt"

printf '\n  ]\n}\n' >> "$results"

echo "==> $failed check(s) failed; wrote ${results#"$root"/}"
