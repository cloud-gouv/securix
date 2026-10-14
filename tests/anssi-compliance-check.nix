# SPDX-FileCopyrightText: 2026 Sébastien Celles <s.celles@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# Regression test for https://github.com/cloud-gouv/securix/issues/293
#
# Builds `anssi-nixos-compliance-check` from stub checks, without a VM, and
# verifies that its JSON output gives each rule the status of its exit code,
# whatever the check prints.

{ pkgs, ... }:
let
  complianceCheck = pkgs.callPackage ../modules/anssi/check-script.nix { } {
    RPASS = pkgs.writeShellScript "check-pass" ''
      echo "Check passed for net.ipv4.icmp_ignore_bogus_error_responses"
    '';
    RTODO = pkgs.writeShellScript "check-todo" ''
      echo "Not implemented: check by hand."
      exit 2
    '';
    RFAIL = pkgs.writeShellScript "check-fail" ''
      echo "No IOMMU detected or not enabled."
      exit 1
    '';
    RNONE = null;
  };
in
pkgs.runCommand "anssi-compliance-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
  ${complianceCheck}/bin/anssi-nixos-compliance-check --json > report.json
  cat report.json
  jq -e '."org.securix.anssi-compliance-check.v1".rules == {
    RPASS: { status: "passed", exitCode: 0, output: "Check passed for net.ipv4.icmp_ignore_bogus_error_responses" },
    RTODO: { status: "not-implemented", exitCode: 2, output: "Not implemented: check by hand." },
    RFAIL: { status: "failed", exitCode: 1, output: "No IOMMU detected or not enabled." },
    RNONE: { status: "not-implemented", exitCode: 2, output: "Check script not defined: cannot be checked." }
  }' report.json
  touch $out
''
