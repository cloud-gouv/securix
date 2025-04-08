# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
# SPDX-FileContributor: Elias Coppens <elias.coppens@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    mapAttrs
    ;
  cfg = config.securix.cloud.openstack-client;
  yaml = pkgs.formats.yaml { };
  cloudOpts = {
    freeformType = yaml.type;
  };

  cloudsNames = builtins.attrNames cfg.clouds;
in
{
  options.securix.cloud.openstack-client = {
    enable = mkEnableOption "the automatic configuration of the OpenStack client";
    defaults = mkOption { type = types.attrsOf types.unspecified; };
    clouds = mkOption { type = types.attrsOf (types.submodule cloudOpts); };
    projects = mkOption { type = types.listOf types.str; };
  };

  config = mkIf cfg.enable {
    environment.etc."openstack/clouds.yaml".source = yaml.generate "clouds.yaml" {
      clouds = mapAttrs (_: cloudConfig: cfg.defaults // cloudConfig) cfg.clouds;
    };

    users.users = mapAttrs (username: config: {
      packages = [
        # Helper to do openstack work.
        (pkgs.writeShellScriptBin "os-run" ''
          usage() {
            echo "usage: os-run <cloud> -- <command> [...]"
            echo "Run in the context of a certain cloud any OpenStack-related command, including Terraform"
            echo "This expects that your Goldwarden is configured correctly."
            echo "Furthermore, it also expects that `$${cloud}_horizon_password` is configured to your Horizon portal password."
          }

          # Check if sufficient arguments are provided.
          if [ "$#" -lt 3 ] || [ "$2" != "--" ]; then
            usage
            exit 1
          fi

          # Parse the cloud argument.
          CLOUD="$1"
          shift # Remove the first argument.
          shift # Remove the '--' separator.

          case "$CLOUD" in
            ${lib.concatStringsSep "|" cloudsNames})
              ;;
            *)
              echo "Invalid cloud name: $CLOUD"
              usage
              exit 1
              ;;
          esac

          # Configure environment variables.
          export OS_CLOUD="$CLOUD"
          export OS_USERNAME="${config.email}"

          # Retrieve the password from Goldwarden.
          export OS_PASSWORD=$(goldwarden logins get --name "''${CLOUD}_horizon_password")
          if [ -z "$OS_PASSWORD" ]; then
            echo "Failed to retrieve password for $CLOUD."
            exit 1
          fi

          # Execute the command.
          exec "$@"
        '')
      ];
    }) config.securix.users.allowedUsers;
    # Wrap `os` to fetch the `OS_PASSWORD` from the Vault.
  };
}
