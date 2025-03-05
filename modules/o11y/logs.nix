# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ config, lib, ... }:
let
  cfg = config.securix.o11y.logs;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
  options.securix.o11y.logs = {
    enable = mkEnableOption "shipment of logs to remote servers";
    serverUrl = mkOption { type = types.str; };
  };

  config = mkIf cfg.enable {
    services.journald.upload = {
      enable = true;
      settings.Upload.URL = cfg.serverUrl;
    };
  };
}
