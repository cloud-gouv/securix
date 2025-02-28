# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  sources ? import ./npins,
  pkgs ? import sources.nixpkgs { },
  securix ? ../securix,
  mainDisk ? "/dev/nvme0n1",
}:
let
  securix = import securix {
    edition = "my-team";
    defaultTags = [ "my-team" ];
    inherit mainDisk pkgs;
  };
  inherit (pkgs) lib;
in
rec {
  users = securix.lib.readInventory ./inventory;
  vpn-profiles = import ./vpn-profiles { inherit lib; };
  # Base system is provided.
  terminals = securix.lib.mkTerminals users vpn-profiles (
    { lib, ... }:
    {
      imports = [
        # Any custom module here...
      ];

      securix = {
        # Le terminal est multi-opérateur
        users.allowAnyOperator = true;

        # Autorise une GUI configurable par l'inventaire.
        graphical-interface.enable = true;

        # Pré-configure des points WiFi par défaut.
        preconfigured-wifi-stations.enable = true;

        # Configure l'agent TPM2 pour SSH.
        ssh.tpm-agent = {
          hostKeys = true;
          sshKeys = true;
        };

        # Configure le VPN pour chaque opérateur
        # avec un pare-feu strict.
        vpn = {
          enable = true;
          firewall.enable = true;
          pskSecretsPath = "your secret path to your PSK.";
        };
      };
    }
  );

  docs = securix.lib.mkDocs { inherit users terminals vpn-profiles; };
}
