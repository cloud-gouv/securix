# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  # rulesets: a set of rules, e.g., { R1 = {...}; R2 = {...}; ... }
  generateOptionHierarchy =
    rulesets:
    let
      levelMapping = {
        "minimal" = 0;
        "intermediary" = 1;
        "reinforced" = 2;
        "high" = 3;
      };
      # helper to generate one rule's option set
      makeRuleOption =
        {
          lib,
          config,
          pkgs,
          ...
        }:
        ruleId: rule:
        {
          anssiRef = lib.mkOption {
            type = lib.types.str;
            default = rule.anssiRef;
            readOnly = true;
            description = "ANSSI reference for rule ${rule.name}";
          };

          enable = lib.mkOption {
            type = lib.types.bool;
            default =
              config.security.anssi.enable
              && levelMapping.${config.security.anssi.level} >= levelMapping.${rule.severity}
              && (rule.category == "base" || rule.category == config.security.anssi.category)
              && lib.all (t: !(lib.elem t config.security.anssi.excludes)) (rule.tags or [ ])
              && (
                ((rule.architectures or [ ]) != [ ])
                -> lib.elem pkgs.stdenv.hostPlatform.linuxArch rule.architectures
              )
              && !config.security.anssi.exceptions ? ${ruleId};

            description = ''
              Enable rule ${rule.name}.
              ${rule.description}
              ANSSI reference: ${rule.anssiRef}.
            '';
          };

          exceptionRationale = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default =
              if config.security.anssi.exceptions ? ${rule.name} then
                config.security.anssi.exceptions.${ruleId}.rationale
              else
                null;
            readOnly = true;
            description = "Optional rationale for disabling or modifying rule ${rule.name}";
          };

          checkScript = lib.mkOption {
            type = lib.types.path; # TODO: or string if we store the script inline
            default = rule.checkScript pkgs;
            description = "Check script for rule ${rule.name}";
          };
        }
        // lib.optionalAttrs (rule ? implementations) {
          implementation = lib.mkOption {
            type = lib.types.enum (lib.attrNames rule.implementations);
            description = "Chosen implementation for this rule.";
          };
        };

      # map each rule in rulesets to the generated option hierarchy
      ruleOptions =
        moduleArgs: moduleArgs.lib.mapAttrs (ruleId: rule: makeRuleOption moduleArgs ruleId rule) rulesets;
      ruleEnabled = config: ruleId: config.security.anssi.rules.${ruleId}.enable;
      enabledRuleConfigs =
        moduleArgs:
        moduleArgs.lib.mapAttrsToList (
          ruleId: rule:
          let
            complexConfigTerm =
              cfg:
              moduleArgs.lib.mkMerge (
                moduleArgs.lib.mapAttrsToList (
                  implName: _:
                  moduleArgs.lib.mkIf (moduleArgs.config.security.anssi.rules.${ruleId}.implementation == implName) (
                    rule.implementations.${implName}.config cfg
                  )
                ) rule.implementations
              );
            simpleConfigFn = rule.config;
            configFn = if rule ? implementations then complexConfigTerm else simpleConfigFn;
          in
          moduleArgs.lib.mkIf (ruleEnabled moduleArgs.config ruleId) (configFn moduleArgs)
        ) rulesets;
    in
    {
      lib,
      config,
      pkgs,
      ...
    }@moduleArgs:
    {
      options.security.anssi.rules = ruleOptions moduleArgs;
      config = lib.mkMerge (enabledRuleConfigs moduleArgs);
    };
}
