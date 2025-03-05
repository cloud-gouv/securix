# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ config, lib, ... }:
let
  cfg = config.securix.o11y.metrics;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    mapAttrsToList
    filterAttrs
    ;
in
{
  options.securix.o11y.metrics = {
    enable = mkEnableOption "shipment of metrics to remote servers";
    serverUrl = mkOption { type = types.str; };
  };

  config = mkIf cfg.enable {
    # This will ship node_exporter-like metrics to the remote servers.
    services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [
        "systemd"
        "processes"
      ];
    };

    # This will ship electricity metrics to the remote servers.
    services.prometheus.exporters.scaphandre = {
      enable = true;
    };

    services.vmagent = {
      enable = true;
      remoteWrite.url = cfg.serverUrl;
      prometheusConfig = {
        scrape_configs =
          mapAttrsToList
            (job_name: cfg: {
              inherit job_name;
              static_configs = [ { targets = [ "127.0.0.1:${builtins.toString cfg.port}" ]; } ];
              metrics_path = if job_name == "scaphandre" then "//metrics" else "/metrics";
            })
            (
              filterAttrs (
                name: cfg:
                # these are not working Prometheus Exporters
                !(builtins.elem name [
                  "assertions"
                  "warnings"
                  "blackbox"
                  "unifi-poller"
                  "domain"
                  "minio"
                  "idrac"
                  "pve"
                  "tor"
                ])
                && cfg.enable
              ) config.services.prometheus.exporters
            );
        global = {
          scrape_interval = "15s";
          external_labels.hostname = config.networking.hostName;
          # TODO: devrait-on-mettre un label supplémentaire d'appartenance d'équipe au niveau des time series exportés?
        };
      };
    };
  };
}
