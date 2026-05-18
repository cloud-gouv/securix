# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ lib, config, ... }:
let
  cfg = config.securix.http-proxy;
  inherit (lib) mkIf concatStringsSep mapAttrs;
  localProxyStream = "127.0.0.1:8080";
in
{
  config = mkIf (cfg.enable && cfg.implementation == "portail") {
    networking.proxy = {
      default = "http://${localProxyStream}";
      noProxy = concatStringsSep "," cfg.exceptions;
    };

    services.portail = {
      enable = true;
      # First request optimization, this avoids the first request to wait for some time needlessly as Portail is pretty fast to boot.
      enableAtBoot = true;
      proxyListenStream = localProxyStream;

      acl.filter.rules = [
        ''
          policy default {
            action allow
          }
        ''
      ];

      settings = {
        # By default, we use ourselves to exit.
        backends = mapAttrs (name: target-address: { inherit target-address; }) cfg.downstreams;
      };
    };

    systemd.services.portail.aliases = [ "http-proxy.service" ];
  };
}
