# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib)
    mkIf
    mkEnableOption
    splitString
    concatStringsSep
    types
    mkOption
    ;
  cfg = config.securix.vpn.firewall;
in
{
  options.securix.vpn.firewall = {
    enable = mkEnableOption "the firewall that guides all packets into the IPsec tunnel only";
    genericRulesetFile = mkOption {
      type = types.path;
      description = "Chemin vers le fichier générique des règles de pare-feu";
    };
  };

  config = mkIf cfg.enable {
    services.resolved = {
      enable = true;
      dnssec = "false";
      llmnr = "false";
      extraConfig = [ "MulticastDNS=false" ];
    };
    networking.firewall.enable = false;
    networking.nftables = {
      enable = true;
      rulesetFile = pkgs.substituteAll {
        src = cfg.genericRulesetFile;
        github_ips = concatStringsSep ",\n" (
          map (l: "\t\t${l}") (splitString "\n" (builtins.readFile ./github-ipv4.txt))
        );
      };
      checkRuleset = false;
    };

    # This is a developer-only feature.
    environment.systemPackages = mkIf config.securix.self.developer [
      # Dynamic firewall control tool.
      (pkgs.writeShellApplication {
        name = "firewall";

        runtimeInputs = [
          pkgs.nftables
          pkgs.gum
        ];

        text = ''
          # Check if running as root
          if [[ $EUID -ne 0 ]]; then
             echo "This script must be run as root"
             exit 1
          fi

          # Display usage
          function usage() {
              echo "Usage: $0 {enable|disable|status}"
              exit 1
          }

          disable_ruleset() {
              echo "Disabling nftables ruleset..."
              
              # Flush all tables
              nft flush ruleset
              echo "All nftables rules flushed. Firewall is disabled."
          }

          enable_ruleset() {
              echo "Enabling nftables ruleset..."

              # Restore rules from the configuration.
              systemctl restart nftables.service
              echo "nftables ruleset re-enabled."
          }

          # Function to check the current status
          check_status() {
              if nft list ruleset | grep -q "chain"; then
                  echo "nftables ruleset is currently ENABLED."
              else
                  echo "nftables ruleset is currently DISABLED."
              fi
          }

          # Main script logic
          case "$1" in
              disable)
                  disable_ruleset
                  ;;
              enable)
                  enable_ruleset
                  ;;
              status)
                  check_status
                  ;;
              *)
                  usage
                  ;;
          esac
        '';
      })
    ];
  };
}
