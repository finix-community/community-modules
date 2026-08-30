{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.programs.efistubmgr;
  ESP_REL_DIR = "${lib.removePrefix "/" (lib.removePrefix cfg.efiMountPoint cfg.bootDir)}";
  efistubHook = pkgs.writeScript "efistub-install" ''
    #!${config.environment.binsh}
    set -euo pipefail

    # ── Paths & metadata ──────────────────────────────────────────────────────

    EFISTUBMGR="${cfg.package}/bin/efistubmgr"

    TIMESTAMP=$(${lib.getExe' config.programs.coreutils.package "date"} +%s)
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
              ${lib.getExe' config.programs.coreutils.package "grep"} -oE 'system-[0-9]+-link' |
              ${lib.getExe' config.programs.coreutils.package "grep"} -oE '[0-9]+' |
              ${lib.getExe' cfg.awk.package "awk"} '{print "rev. " $1}'
            return
            ;;
        esac
      done
    }

    is_kept_timestamp() {
      printf '%s\n' "$KEEP_TIMESTAMPS" | grep -Fxq "$1"
    }

    is_seen_timestamp() {
      printf '%s\n' "$ORPHAN_TIMESTAMPS" | grep -Fxq "$1"
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
    ESP_REL_DIR_WIN=$(printf '%s' "${ESP_REL_DIR}" | ${lib.getExe' config.programs.coreutils.package "tr"} '/' '\\')
    ESP_KERNEL_PATH="\\''${ESP_REL_DIR_WIN}\\kernel-$TIMESTAMP.efi"
    ESP_INITRD_PATH="\\''${ESP_REL_DIR_WIN}\\initrd-$TIMESTAMP"
    NEW_ID=$("$EFISTUBMGR" create "${cfg.efiMountPoint}" \
      '\EFI\finix\kernel-'"$TIMESTAMP"'.efi' \
      "$DESCRIPTION" \
      "initrd=$ESP_INITRD_PATH init=$INIT $PARAMS" \
      --timestamp "$TIMESTAMP")

    echo "==> Created Boot$NEW_ID"

    # ── Keep newest generations ───────────────────────────────────────────────

    IFS='
    '
    set -- $("$EFISTUBMGR" list)
    unset IFS

    echo "==> $# generation(s) in NVRAM"

    i=0
    KEEP_TIMESTAMPS=
    for line in "$@"; do
        i=$((i + 1))
        [ "$i" -le "${toString cfg.maxGenerations}" ] || break
        ts=$(printf '%s\n' "$line" | ${lib.getExe' cfg.awk.package "awk"} '{print $2}')
        KEEP_TIMESTAMPS="$KEEP_TIMESTAMPS
    $ts"
    done

    PRUNE_IDS=
    if [ "$#" -gt "${toString cfg.maxGenerations}" ]; then
        i=0
        for line in "$@"; do
            i=$((i + 1))
            [ "$i" -gt "${toString cfg.maxGenerations}" ] || continue
            id=$(printf '%s\n' "$line" | ${lib.getExe' cfg.awk.package "awk"} '{print $1}')
            ts=$(printf '%s\n' "$line" | ${lib.getExe' cfg.awk.package "awk"} '{print $2}')

            "$EFISTUBMGR" delete "$id"
            PRUNE_IDS="$PRUNE_IDS
    $ts $id"
        done
    fi

    # ── Remove orphaned ESP files ─────────────────────────────────────────────

    ORPHAN_TIMESTAMPS=

    for f in "${cfg.bootDir}"/kernel-*.efi "${cfg.bootDir}"/initrd-*; do
      [ -e "$f" ] || continue

      base=$(basename "$f")
      file_ts="''${base#*-}"
      file_ts="''${file_ts%.efi}"

      if ! is_kept_timestamp "$file_ts" &&
         ! is_seen_timestamp "$file_ts"; then
         ORPHAN_TIMESTAMPS=$(printf '%s\n%s' "$ORPHAN_TIMESTAMPS" "$file_ts")
      fi
    done
    prune_id_for_ts() {
      printf '%s\n' "$PRUNE_IDS" | awk -v ts="$1" '$1 == ts { print $2; exit }'
    }

    for ts in $ORPHAN_TIMESTAMPS; do
      prune_id=$(prune_id_for_ts "$ts")
      if [ -n "$prune_id" ]; then
        echo "==> Removing orphaned ESP files kernel-$ts.efi + initrd-$ts" \
        "(timestamp $ts, removed matching Boot$prune_id NVRAM entry)"
    else
      echo "==> Removing orphaned ESP files kernel-$ts.efi + initrd-$ts" \
      "(timestamp $ts, no matching NVRAM entry)"
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
      default = ''$LABEL''${REV:+ $REV} * $(${lib.getExe' config.programs.coreutils.package "date"} -d "@$TIMESTAMP" '+%Y-%m-%d %H:%M:%S %Z')'';
      description = "How each generation appears in the UEFI boot picker, REV and LABEL are provided as is in the install script. Non ASCII characters may stop it from appearing in the Boot Options";
    };

    bootSpec = lib.mkOption {
      type = lib.types.str;
      default = "$1/boot.json";
      description = ''
        Path to a boot specification, best to leave as default unless you know what you are doing
      '';
    };
    awk.package = lib.mkOption {
      type = lib.types.package;
      default = config.programs.coreutils.package;
      defaultText = lib.literalExpression "config.programs.coreutils.package";
      description = ''
        The package to use for awk
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
