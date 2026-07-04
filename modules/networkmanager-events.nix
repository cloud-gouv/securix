# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.securix.networkmanager.events;
  inherit (lib)
    mkOption
    types
    mkIf
    mkEnableOption
    concatStringsSep
    attrNames
    sort
    ;

  sortedHandlerNames = sort (a: b: a < b) (attrNames cfg.handlers);
  mkHandlerScript =
    name:
    {
      event,
      matchConnectionId,
      script,
    }:
    ''
      if [[ "$event" == "${event}" && "$CONNECTION_ID" == "${matchConnectionId}" ]]; then
        logger "[securix-nm-events-hook] running handler ${name}..."
        ${script}
      fi
    '';
in
{
  options.securix.networkmanager.events = {
    enable = mkEnableOption "an event-based system to respond to NetworkManager events";

    handlers = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            event = mkOption {
              type = types.enum [
                "vpn-up"
                "vpn-down"
              ];
              description = "NetworkManager event type to handle";
            };

            matchConnectionId = mkOption {
              type = types.str;
              description = ''
                Shell pattern to match against connection ID.

                You can use `$user` as a placeholder to refer to the user who emitted that event.
                This user is calculated on a best effort basis based on who is the graphical user connected to the system.
              '';
            };

            script = mkOption {
              type = types.lines;
              description = "Shell script to execute when event matches";
            };
          };
        }
      );
      default = { };
      description = "Event handlers for NetworkManager dispatcher";
    };
  };

  config = mkIf cfg.enable {
    networking.networkmanager.dispatcherScripts = [
      {
        type = "basic";
        source = pkgs.writeText "10-securix-nm-events-hook" ''
          # This retrieves the caller user of the dispatcher.
          # NOTE(Ryan): this logic is brittle. on a multi-seat system,
          # there's multiple results.
          # NetworkManager should pass who sent the D-Bus message as an environment variable.
          # https://gitlab.freedesktop.org/NetworkManager/NetworkManager/-/work_items/1976
          user=$(loginctl list-sessions --no-legend | ${pkgs.gawk}/bin/awk '{print $3}' | sort -u | grep -vE '^(root|gdm)$')

          if [[ "$2" != "vpn-up" && "$2" != "vpn-down" ]]; then
            logger "[securix-nm-events-hook] exit: event $2, waiting for vpn-up or vpn-down event"
            exit
          fi

          logger "[securix-nm-events-hook] evaluating all handlers..."
          event="$2"
          ${concatStringsSep "\n" (map (name: mkHandlerScript name cfg.handlers.${name}) sortedHandlerNames)}
        '';
      }
    ];
  };
}
