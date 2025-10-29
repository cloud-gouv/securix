# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT
{ lib, ... }:
let
  inherit (lib) mkOption types mkIf;
in
{
  mkRule = { number, description, module, config }: {
    options.securix.anssi-rules."r${toString number}".enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable ANSSI rule R${toString number}

        ${description}
      '';
    };

    config = mkIf config.securix.anssi-rules."r${toString number}".enable module;
  };

  # This is an external rule, i.e. a rule enabled and enforced by non-OS policies.
  mkExternalRule = { name, description }: "";
  mkNotApplicableRule = { number, description, reason }: {
    options.securix.anssi-rules."r${toString number}".enable = mkOption {
      type = types.bool;
      default = false;
      readOnly = false;
      description = ''
        Enable ANSSI rule R${toString number}

        ${description}

        This rule is not applicable to Securix due to:
        ${reason}

        Enabling it is not possible.
      '';
    };
  };

  # This is a rule that cannot be disabled by the system.
  mkAlwaysEnabledRule = { number, description, reason, config }: {
    options.securix.anssi-rules."r${toString number}".enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable ANSSI rule R${toString number}

        ${description}

        This rule cannot be disabled.
      '';

      config = {
        assertions = [
          {
            assertion = config.securix.anssi-rules."r${toString number}".enable;
            message = "ANSSI rule R${toString number} cannot be disabled due to ${reason}";
          }
        ];
      };
  };

  mkAlwaysDisabledRule = { name, description, reason }: "";
  mkUnimplementedRule = { name, description }: "";
}
