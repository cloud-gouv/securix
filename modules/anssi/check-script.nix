# SPDX-FileCopyrightText: 2026 Sébastien Celles <s.celles@gmail.com>
#
# SPDX-License-Identifier: MIT

# Builds `anssi-nixos-compliance-check` from { RXX = <check script or null>; }.
# A check exits 0 when it passes, 2 when it is not implemented or cannot be
# checked, and with any other status when it fails.
{
  lib,
  jq,
  writeShellScriptBin,
}:
checkScripts:
let
  mkCheckSingularRule =
    ruleId: checkScript:
    if checkScript == null then
      ''
        statuses[${ruleId}]=2
        results[${ruleId}]="Check script not defined: cannot be checked."
      ''
    else
      ''
        run_check ${ruleId} ${checkScript}
      '';
in
writeShellScriptBin "anssi-nixos-compliance-check" ''
  declare -A results
  declare -A statuses

  run_check() {
    local status=0 result
    result=$(bash "$2") || status=$?
    results["$1"]=$result
    statuses["$1"]=$status
  }

  status_name() {
    case "$1" in
      0) echo passed ;;
      2) echo not-implemented ;;
      *) echo failed ;;
    esac
  }

  ${lib.concatStringsSep "\n" (lib.mapAttrsToList mkCheckSingularRule checkScripts)}

  if [[ "''${1-}" == "--json" ]]; then
    for rule in "''${!results[@]}"; do
      ${jq}/bin/jq -n \
        --arg rule "$rule" \
        --arg status "$(status_name "''${statuses[$rule]}")" \
        --argjson exitCode "''${statuses[$rule]}" \
        --arg output "''${results[$rule]}" \
        '{ ($rule): { $status, $exitCode, $output } }'
    done | ${jq}/bin/jq -S -s '{ "org.securix.anssi-compliance-check.v1": { rules: (add // { }) } }'
    exit 0
  fi

  # Output the results in a matrix format
  echo "ANSSI Compliance Check Results:"
  for rule in "''${!results[@]}"; do
    case "$(status_name "''${statuses[$rule]}")" in
      passed) colour=32 ;;
      not-implemented) colour=33 ;;
      *) colour=31 ;;
    esac
    printf "\033[%sm%-40s : %s\033[0m\n" "$colour" "$rule" "''${results[$rule]}"
  done
''
