# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  sources ? import ./npins,
  pkgs ? import sources.nixpkgs { },
  securixSrc ? ../..,
}:
let
  securix = import securixSrc {
    edition = "my-team";
    defaultTags = [ "my-team" ];
    inherit pkgs;
  };
in
rec {
  machines = securix.lib.readInventory ./inventory;
  vpn-profiles = { };
  # Base system is provided.
  terminals =
    securix.lib.mkTerminals
      {
        inherit machines vpn-profiles;
        edition = "test-edition";
        mainDisk = "/dev/nvme0n1";
      }
      (
        { ... }:
        {
          imports = [ ./operators.nix ];

          securix = {
            # Le terminal est multi-opérateur
            users.allowAnyOperator = true;

            # Autorise une GUI configurable par l'inventaire.
            graphical-interface = {
              enable = true;
              variant = "kde";
            };

            # Configure l'agent TPM2 pour SSH.
            ssh.tpm-agent = {
              hostKeys = true;
              sshKeys = true;
            };

            # Configure le VPN pour chaque opérateur
            # avec un pare-feu strict.
            vpn = {
              netbird.enable = true;
              firewall = {
                enable = true;
                genericRulesetFile = ./nftable.nft;
              };
            };
          };
        }
      );

  docs = securix.lib.mkDocs { inherit machines terminals vpn-profiles; };
}
