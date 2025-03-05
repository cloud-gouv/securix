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
    ;
in
{
  options.securix.o11y.metrics = {
    enable = mkEnableOption "shipment of metrics to remote servers";
    serverUrl = mkOption { type = types.str; };
  };

  config = mkIf cfg.enable {
    services.vmagent = {
      enable = true;
      remoteWrite.url = cfg.serverUrl;
    };
  };
}
