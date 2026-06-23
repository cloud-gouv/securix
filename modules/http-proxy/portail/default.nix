# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ lib, config, ... }:
let
  cfg = config.securix.http-proxy;
  automaticCfg = config.securix.automatic-http-proxy;
  inherit (lib) mkIf concatStringsSep mapAttrs mapAttrsToList filterAttrs optionalAttrs concatMapAttrs;
  localProxyStream = "127.0.0.1:8080";
in
{
  imports = [ ./tray.nix ];

  config = mkIf (cfg.enable && cfg.implementation == "portail") {
    networking.proxy = {
      default = "http://${localProxyStream}";
      noProxy = concatStringsSep "," cfg.exceptions;
    };

    securix.networkmanager.events.handlers = concatMapAttrs (
      eventName:
      { matchConnectionId, proxyToActuate }:
      let
        proxyMetadata =
          automaticCfg.proxies.${proxyToActuate}
            or (throw "Proxy '${proxyToActuate}' is not defined in the list of automatically managed proxies");
      in
      {
        "${eventName}-up" = {
          event = "vpn-up";
          inherit matchConnectionId;

          script = ''
            # Hook for proxy ${proxyToActuate} related to VPN ${proxyMetadata.vpn}
            # For connection ID: ${matchConnectionId}
            logger "[Portail proxy hook] Automatically switching to proxy ${proxyToActuate}"
            ${config.services.portail.package}/bin/portail rpc set-default-backend ${proxyToActuate}
            # TODO: only run this if the auth method uses ssh tunnels.
            # TODO: use Portail's native SSH tunnels later on.
            systemctl --user -M "$user"@ stop "ssh-tunnel-to-*" --all
            systemctl --user -M "$user"@ start ssh-tunnel-to-${proxyToActuate}.service
          '';
        };

        "${eventName}-down" = {
          event = "vpn-down";
          inherit matchConnectionId;

          script = ''
            # Hook for proxy ${proxyToActuate}
            # For connection ID: ${matchConnectionId}
            logger "[Portail proxy hook] Automatically switching to no proxy"
            ${config.services.portail.package}/bin/portail rpc unset-default-backend ${proxyToActuate}
            # TODO: only run this if the auth method uses ssh tunnels.
            # TODO: use Portail's native SSH tunnels later on.
            systemctl --user -M "$user"@ stop "ssh-tunnel-to-${proxyToActuate}.service"
          '';
        };
      }
    ) automaticCfg.networkmanager.events.handlers;

    # To allow users to call `portailctl`
    environment.systemPackages = [
      config.services.portail.package
    ];

    # Manage dynamically defined proxies
    systemd.services.portail-dynamic-updates = 
    let
      isDynamic = _: proxy: proxy.definition == "dynamic";
    in
    {
      description = "Update dynamically defined proxies target addresses";
      after = [ "portail-rpc.socket" "portail.service" ];
      requires = [ "portail-rpc.socket" "portail.service" ];
      path = [ config.services.portail.package ];
      serviceConfig = {
        DynamicUser = true;
        SupplementaryGroups = [ "portail-admins" ];
        Type = "oneshot";
        Restart = "on-failure";
        RestartSec = 5;
        LoadCredential = mapAttrsToList (id: { remotePath, ... }: "${id}:${remotePath}") (filterAttrs isDynamic config.securix.automatic-http-proxy.proxies);
      };
      script = 
      let
        mkUpdateScript = id: { remotePath, ... }: ''
          echo "Updating dynamic proxy ${id}..."
          source $CREDENTIALS_DIRECTORY/${id}
          portail rpc update-dynamic-backend ${id} --target-address "$ADDRESS:$PORT"
          echo "Updated!"
        '';
      in
        # HACK(Ryan): this is a layer violation but it should disappear as soon as we tear down the proxy abstraction once g3proxy goes away.
        # There's a too large feature difference between Portail and anything else.
        concatStringsSep "\n" (mapAttrsToList mkUpdateScript (filterAttrs isDynamic config.securix.automatic-http-proxy.proxies));
    };

    # every time, portail starts successfully, start the dynamic updates.
    systemd.services.portail.unitConfig.OnSuccess = [ "portail-dynamic-updates.service" ];

    # This group is allowed to update any dynamic backend (if there's any).
    users.groups.portail-admins = { };
    services.portail = {
      enable = true;
      # First request optimization, this avoids the first request to wait for some time needlessly as Portail is pretty fast to boot.
      enableAtBoot = true;
      proxyListenStream = localProxyStream;

      acl.filter.rules."99-default" = ''
        policy default {
          action allow
        }
      '';

      settings = {
        # By default, we use ourselves to exit.
        backends = mapAttrs (name: target-address: {
          dynamic = target-address == null;
        } // optionalAttrs (target-address != null) {
          inherit target-address;
        }) cfg.downstreams;
        rpc = {
          trusted-groups = [ "operator" ];
          admin-groups = [ "portail-admins" ];
        };
      };
    };

    systemd.services.portail.aliases = [ "http-proxy.service" ];
  };
}
