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
   securixPkgs = import securix {
    edition = "my-team";
    defaultTags = [ "my-team" ];
  inherit pkgs;
  };
  inherit (pkgs) lib;
in
rec {
  users = securixPkgs.lib.readInventory ./inventory;
  vpn-profiles = import ./vpn-profiles { inherit lib; };
  # Base system is provided.
 terminals = securixPkgs.lib.mkTerminals { inherit users vpn-profiles; edition = "my-team"; } (
    { lib, ... }:
    {
      imports = [
        # Any custom module here...
      ];

      securix = {
  self.mainDisk = mainDisk;
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

  docs = securixPkgs.lib.mkDocs { inherit users terminals vpn-profiles; };
}
