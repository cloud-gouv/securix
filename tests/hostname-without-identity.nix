# SPDX-FileCopyrightText: 2026 T2an
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }:
let
  terminal-without-identity = libSecurix.mkTerminal {
    name = "no-identity";
    userSpecificModule = { };
    vpnProfiles = { };
    modules = [
      {
        securix = {
          graphical-interface.variant = "sway";
          self = {
            mainDisk = "/dev/nvme0n1";
            machine.hardwareSKU = "x280";
          };
        };
      }
    ];
  };
  hostname = terminal-without-identity.system.config.networking.hostName;
in
pkgs.runCommand "hostname-without-identity" { } ''
  [ "${hostname}" = "securix-unbranded-unknown-machine" ] || {
    echo "unexpected hostname: ${hostname}" >&2
    exit 1
  }
  touch $out
''
