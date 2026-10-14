# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  pkgs,
  config,
  lib,
  ...
}:

let
  inherit (lib) mkEnableOption mkOption types;

  cfg = config.security.anssi;
  rulesets = import ./ruleset.nix { inherit lib; };
  levelMapping = {
    "minimal" = 0;
    "intermediary" = 1;
    "reinforced" = 2;
    "high" = 3;
  };

  # rules.* must follow the format used earlier:
  # {
  #   name = "...";
  #   category = "client" / "server" / "base";
  #   severity = "minimal" / "intermediary" / "reinforced" / "high";
  #   tags = [ "kernel" ... ];
  #   config = f: { ... };
  #   checkScript = pkgs: pkgs.writeShellScript ...
  # }

  # Look at all rules that are not enabled.
  # Determine why they are not enabled:
  # - if there's an exception for it, use it.
  # - if it's excluded via a tag, use it.
  # - if it's excluded via architecture, use it.
  # - if it's out of the scope for the category, use it.
  # - if it's out of the scope for the level, use it.
  # - otherwise, mark it unknown.
  # Determine why a rule is not enabled.
  determineExclusionReason =
    ruleId: rule:
    if !cfg.rules.${ruleId}.enable then
      # Check if it's excluded via a clear mechanism.
      let
        tagExclusions = lib.filter (tag: lib.elem tag (rule.tags or [ ])) cfg.excludes;
        categoryExclusion = rule.category != "base" && rule.category != cfg.category;
        levelExclusion = levelMapping.${rule.severity} > levelMapping.${cfg.level};
        architectureExclusion =
          if (rule.architectures or [ ]) != [ ] then
            !lib.elem pkgs.stdenv.hostPlatform.linuxArch rule.architectures
          else
            false;
      in
      if tagExclusions != [ ] then
        {
          reason = "excluded by tag ${lib.concatStringsSep ", " tagExclusions}";
          via = "tag";
          exclusionTags = tagExclusions;
        }
      else if categoryExclusion then
        {
          reason = "out of scope for category '${cfg.category}' (${rule.category})";
          via = "category";
          requiredCategory = rule.category;
        }
      else if levelExclusion then
        {
          reason = "out of scope for level ${cfg.level} < ${rule.severity}";
          via = "level";
          requiredLevel = rule.severity;
        }
      else if architectureExclusion then
        {
          reason = "out of scope for architecture '${pkgs.stdenv.hostPlatform.linuxArch}'";
          via = "architecture";
          requiredArchitectures = rule.architectures or [ ];
        }
      else if lib.hasAttr ruleId cfg.exceptions then
        {
          reason = "excluded by explicit exception: ${cfg.exceptions.${ruleId}.rationale}";
          via = "exception";
          rationale = cfg.exceptions.${ruleId}.rationale;
        }
      else
        {
          reason = "could not understand why this rule was excluded, the user must have set the `enable = false;` forcibly via the module system bypassing the governance system. This is a non-compliant.";
          via = "unknown";
        }
    else
      null;

  generateRuleEntry =
    ruleId: rule:
    {
      enabled = cfg.rules.${ruleId}.enable;
      anssiRef = cfg.rules.${ruleId}.anssiRef;
      knownCheckScript = rule.checkScript pkgs;
    }
    // lib.optionalAttrs (cfg.exceptions ? ruleId) {
      declaredExceptionRationale = cfg.exceptions.${ruleId}.rationale;
    }
    // lib.optionalAttrs (rule ? implementations) {
      implementation = cfg.rules.${ruleId}.implementation;
    };

  complianceReport = {
    "org.securix.anssi-compliance.v1" = {
      guideVersion = "2.0";
      rules = lib.mapAttrsToList (ruleId: rule: generateRuleEntry ruleId rule) rulesets;
      targetLevel = cfg.level;
      hostname = config.networking.hostName;
      domain = config.networking.domain or null;
      targetSystemCategory = cfg.category;
      exclusions = lib.mapAttrs determineExclusionReason (
        lib.filterAttrs (ruleId: _: !cfg.rules.${ruleId}.enable) rulesets
      );
    };
  };
in
{
  imports = [
    # This will generate `security.anssi.rules.RXX.{anssiRef,enable,checkScript}` options and so on.
    ((import ./generator.nix).generateOptionHierarchy rulesets)
  ];

  options.security.anssi = {
    enable = mkEnableOption "ANSSI compliance for GNU/Linux systems (v2.0)";

    level = mkOption {
      type = types.enum [
        "minimal"
        "intermediary"
        "reinforced"
        "high"
      ];
      default = "minimal";
      description = "Select desired ANSSI compliance level.";
    };

    category = mkOption {
      type = types.enum [
        "base"
        "client"
        "server"
      ];
      default = "base";
      description = "Rule category to activate.";
    };

    excludes = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Tags to exclude (e.g. [ \"kernel\" \"no-ipv6\" ])";
    };

    exceptions = mkOption {
      type = types.attrsOf (
        types.submodule (_: {
          options.rationale = mkOption { type = types.lines; };
        })
      );
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    system.build.complianceReport = complianceReport;
    system.build.complianceReportDocument = pkgs.writers.writeJSON "anssi-compliance.json" complianceReport;
    system.build.complianceCheckScript =
      let
        mkCheckSingularRule = ruleId: rule: ''
          # Check for rule ${ruleId}
          if [ -n "${rule.checkScript}" ]; then
            result=$(bash -c "${rule.checkScript}")
            results["${ruleId}"]=$result
          else
            results["${ruleId}"]="Check script not defined: cannot be checked."
          fi
        '';
      in
      pkgs.writeShellScriptBin "anssi-nixos-compliance-check" ''
        declare -A results

        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList mkCheckSingularRule (
            lib.filterAttrs (_: rule: rule.enable) config.security.anssi.rules
          )
        )}

        # Output the results in a matrix format
        echo "ANSSI Compliance Check Results:"
        for rule in "''${!results[@]}"; do
          result="''${results[$rule]}"
          if [[ "$result" =~ .*TODO.* ]]; then
            printf "\033[33m%-40s : %s\033[0m\n" "$rule" "$result"
          elif [[ "$result" =~ (fail|WARNING|DIVERGENCE|UNSET|error|not\ completed|incomplete) ]]; then
            printf "\033[31m%-40s : %s\033[0m\n" "$rule" "$result"
          else
            printf "\033[32m%-40s : %s\033[0m\n" "$rule" "$result"
          fi
        done
      '';

    environment.systemPackages = [ config.system.build.complianceCheckScript ];
  };
}
