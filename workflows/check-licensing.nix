# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

# On vérifie que la conformité en licence de Sécurix reste valide.
{ runs-on, commonSteps, ... }:
{
  name = "[Sécurix] REUSE Licensing conformance";

  on =
  {
    pull_request = { };
    push = {
      branches = [ "main" ];
    };
  };

  jobs = {
    reuse_lint = {
      inherit runs-on;
      steps = [
        commonSteps.checkout
        commonSteps.install-nix
        commonSteps.setup-nix-cache
        {
          name = "Check for REUSE compliance";
          run = "nix-shell --run 'reuse --root . lint'";
        }
      ];
    };
  };
}

