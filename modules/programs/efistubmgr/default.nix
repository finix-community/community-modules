{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.programs.efistubmgr;
  ESP_REL_DIR = "${lib.removePrefix "/" (lib.removePrefix cfg.efiMountPoint cfg.bootDir)}";
  efistubHook = pkgs.writeShellScript "efistub-install" ''
    set -euo pipefail

    # ── Paths & metadata ──────────────────────────────────────────────────────

    EFISTUBMGR="${cfg.package}/bin/efistubmgr"

    TIMESTAMP=$(${pkgs.coreutils}/bin/date +%s)
    KERNEL_PATH="${cfg.bootDir}/kernel-$TIMESTAMP.efi"
    INITRD_PATH="${cfg.bootDir}/initrd-$TIMESTAMP"

    # ── Helpers ───────────────────────────────────────────────────────────────

    get_rev() {
      local target="$1"
      local path="$2"
      local link

      for link in /nix/var/nix/profiles/system-*-link; do
        [ -e "$link" ] || continue

        case "$(readlink "$link")" in
          "$target"|"$path")
            printf '%s\n' "$link" |
              ${pkgs.gnugrep}/bin/grep -oE 'system-[0-9]+-link' |
              ${pkgs.gnugrep}/bin/grep -oE '[0-9]+' |
              ${pkgs.gawk}/bin/awk '{print "rev. " $1}'
            return
            ;;
        esac
      done
    }

    is_kept_timestamp() {
      local needle="$1"

      for ts in "''${KEEP_TIMESTAMPS[@]}"; do
        [ "$ts" = "$needle" ] && return 0
      done

      return 1
    }

    is_seen_timestamp() {
      local needle="$1"

      for ts in "''${ORPHAN_TIMESTAMPS[@]}"; do
        [ "$ts" = "$needle" ] && return 0
      done

      return 1
    }

    # ── Validate & read bootspec ──────────────────────────────────────────────

    [ -r ${cfg.bootSpec} ] ||
      { echo "ERROR: boot.json not found at ${cfg.bootSpec}"; exit 1; }

    KERNEL=$(${pkgs.jq}/bin/jq -r '."org.nixos.bootspec.v1".kernel' "${cfg.bootSpec}")
    INITRD=$(${pkgs.jq}/bin/jq -r '."org.nixos.bootspec.v1".initrd' "${cfg.bootSpec}")
    INIT=$(${pkgs.jq}/bin/jq -r '."org.nixos.bootspec.v1".init' "${cfg.bootSpec}")
    PARAMS=$(${pkgs.jq}/bin/jq -r '."org.nixos.bootspec.v1".kernelParams | join(" ")' "${cfg.bootSpec}")
    LABEL=$(${pkgs.jq}/bin/jq -r '."org.nixos.bootspec.v1".label // empty' "${cfg.bootSpec}")
    TOPLEVEL=$(${pkgs.jq}/bin/jq -r '."org.nixos.bootspec.v1".toplevel // empty' "${cfg.bootSpec}")

    [ -z "$LABEL" ] || [ "$LABEL" = "null" ] && LABEL="Finix"
    [ -z "$TOPLEVEL" ] && TOPLEVEL="$1"

    REV=$(get_rev "$TOPLEVEL" "$1")
    DESCRIPTION="${cfg.bootEntry}"

    # ── Install kernel & initrd ───────────────────────────────────────────────

    mkdir -p ${cfg.bootDir}

    echo "==> Installing kernel and initrd (timestamp: $TIMESTAMP)"
    install -m 0644 "$KERNEL" "$KERNEL_PATH"
    install -m 0644 "$INITRD" "$INITRD_PATH"

    # ── Secure Boot ───────────────────────────────────────────────────────────

    if [ "${lib.boolToString cfg.secureBoot.enable}" = "true" ]; then
      if [ -d ${cfg.secureBoot.keyLocation} ]; then
        echo "==> sbctl: signing kernel"
        ${cfg.secureBoot.sbctl}/bin/sbctl sign "$KERNEL_PATH" || \
          echo "WARNING: sbctl signing failed, but continuing (Secure Boot may not work)"
      fi
    fi

    # ── Create NVRAM entry ────────────────────────────────────────────────────

    echo "==> Creating new primary entry: $DESCRIPTION (timestamp $TIMESTAMP)"
    ESP_REL_DIR_WIN=$(${pkgs.coreutils}/bin/tr '/' '\\' <<< "${ESP_REL_DIR}")
    ESP_KERNEL_PATH="\\''${ESP_REL_DIR_WIN}\\kernel-$TIMESTAMP.efi"
    ESP_INITRD_PATH="\\''${ESP_REL_DIR_WIN}\\initrd-$TIMESTAMP"
    NEW_ID=$("$EFISTUBMGR" create "${cfg.efiMountPoint}" \
      '\EFI\finix\kernel-'"$TIMESTAMP"'.efi' \
      "$DESCRIPTION" \
      "initrd=$ESP_INITRD_PATH init=$INIT $PARAMS" \
      --timestamp "$TIMESTAMP")

    echo "==> Created Boot$NEW_ID"

    # ── Keep newest generations ───────────────────────────────────────────────

    mapfile -t GENERATIONS < <("$EFISTUBMGR" list)
    echo "==> ''${#GENERATIONS[@]} finix generation(s) in NVRAM"

    KEEP_TIMESTAMPS=()
    for line in "''${GENERATIONS[@]:0:${toString cfg.maxGenerations}}"; do
      KEEP_TIMESTAMPS+=(
        "$(${pkgs.gawk}/bin/awk '{print $2}' <<<"$line")"
      )
    done

    declare -A PRUNE_IDS

    if [ "''${#GENERATIONS[@]}" -gt "${toString cfg.maxGenerations}" ]; then
      for line in "''${GENERATIONS[@]:${toString cfg.maxGenerations}}"; do
        id=$(${pkgs.gawk}/bin/awk '{print $1}' <<<"$line")
        ts=$(${pkgs.gawk}/bin/awk '{print $2}' <<<"$line")

        "$EFISTUBMGR" delete "$id"
        PRUNE_IDS["$ts"]="$id"
      done
    fi

    # ── Remove orphaned ESP files ─────────────────────────────────────────────

    ORPHAN_TIMESTAMPS=()

    for f in "${cfg.bootDir}"/kernel-*.efi "${cfg.bootDir}"/initrd-*; do
      [ -e "$f" ] || continue

      base=$(basename "$f")
      file_ts="''${base#*-}"
      file_ts="''${file_ts%.efi}"

      if ! is_kept_timestamp "$file_ts" &&
         ! is_seen_timestamp "$file_ts"; then
        ORPHAN_TIMESTAMPS+=("$file_ts")
      fi
    done

    for ts in "''${ORPHAN_TIMESTAMPS[@]}"; do
      if [ -n "''${PRUNE_IDS[$ts]:-}" ]; then
        echo "==> Removing orphaned ESP files kernel-$ts.efi + initrd-$ts" \
          "(ts $ts, removed matching Boot''${PRUNE_IDS[$ts]} NVRAM entry)"
      else
        echo "==> Removing orphaned ESP files kernel-$ts.efi + initrd-$ts" \
          "(ts $ts, no matching NVRAM entry)"
      fi

      rm -f "${cfg.bootDir}/kernel-$ts.efi" "${cfg.bootDir}/initrd-$ts"
    done

    echo "==> EFISTUB setup complete"
  '';
in
{
  meta.maintainers = with lib.maintainers; [
    Z4il
  ];
  options.programs.efistubmgr = {
    enable = lib.mkEnableOption "Minimal EFISTUB manager written in Rust.";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix {}";
      description = ''
        The package to use for efistubmgr.
      '';
    };
    efiMountPoint = lib.mkOption {
      type = lib.types.str;
      default = "${config.boot.loader.efi.efiSysMountPoint}";
      description = ''
        Where the EFI System Partition is mounted.
      '';
    };
    maxGenerations = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = ''
        Number of generations (positive and >0) to show in UEFI boot picker/to keep in NVRAM.
      '';
    };
    secureBoot = {
      enable = lib.mkEnableOption "Whether to enable secure boot or not.";
      keyLocation = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/sbctl/keys";
        description = ''
          Location of the keys used for secureboot signing, bring your own.
        '';
      };
      sbctl = lib.mkPackageOption pkgs "sbctl" { };
    };
    bootDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.efiMountPoint}/EFI/finix";
      description = ''
        Where to save the kerenl stubs and initrd
      '';
    };
    bootEntry = lib.mkOption {
      type = lib.types.str;
      default = ''$LABEL''${REV:+ $REV} * $(${pkgs.coreutils}/bin/date -d "@$TIMESTAMP" '+%Y-%m-%d %H:%M:%S %Z')'';
      description = "How each generation appears in the UEFI boot picker, REV and LABEL are provided as is in the install script. Non ASCII characters may stop it from appearing in the Boot Options";
    };

    bootSpec = lib.mkOption {
      type = lib.types.str;
      default = "$1/boot.json";
      description = ''
        Path to a boot specification, best to leave as default unless you know what you are doing
      '';
    };
  };
  config = {
    environment = lib.mkIf cfg.enable {
      systemPackages = [
        cfg.package
        pkgs.jq
      ];
    };
    boot.loader.script = {
      enable = true;
      installHook = efistubHook;
    };
  };
}
