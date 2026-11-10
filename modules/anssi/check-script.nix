# SPDX-FileCopyrightText: 2026 Sébastien Celles <s.celles@gmail.com>
#
# SPDX-License-Identifier: MIT

# Builds `anssi-nixos-compliance-check` from { RXX = <check script or null>; }.
# A check exits 0 when it passes and with any other status when it fails.
# Rules without a check script are reported as not implemented.
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
        status_names[${ruleId}]=not-implemented
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
  declare -A status_names

  run_check() {
    local status=0 result
    result=$(bash "$2") || status=$?
    results["$1"]=$result
    statuses["$1"]=$status
    if (( status == 0 )); then
      status_names["$1"]=passed
    else
      status_names["$1"]=failed
    fi
  }

  ${lib.concatStringsSep "\n" (lib.mapAttrsToList mkCheckSingularRule checkScripts)}

  if [[ "''${1-}" == "--json" ]]; then
    for rule in "''${!results[@]}"; do
      ${jq}/bin/jq -n \
        --arg rule "$rule" \
        --arg status "''${status_names[$rule]}" \
        --argjson exitCode "''${statuses[$rule]}" \
        --arg output "''${results[$rule]}" \
        '{ ($rule): { $status, $exitCode, $output } }'
    done | ${jq}/bin/jq -S -s '{ "org.securix.anssi-compliance-check.v1": { rules: (add // { }) } }'
    exit 0
  fi

  # Output the results in a matrix format
  echo "ANSSI Compliance Check Results:"
  for rule in "''${!results[@]}"; do
    case "''${status_names[$rule]}" in
      passed) colour=32 ;;
      not-implemented) colour=33 ;;
      *) colour=31 ;;
    esac
    printf "\033[%sm%-40s : %s\033[0m\n" "$colour" "$rule" "''${results[$rule]}"
  done
''
