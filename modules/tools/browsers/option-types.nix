# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
# SPDX-FileContributor: Elias Coppens <elias.coppens@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ lib, ... }:
let
  inherit (lib) mkOption;
  inherit (lib.types)
    str
    bool
    listOf
    nullOr
    ;
in
{
  bookmarkType = {
    options = {
      icon = mkOption {
        type = str;
        default = "";
        description = ''
          Name of the icon of the bookmark.
        '';
      };

      href = mkOption {
        type = str;
        description = ''
          URL of the website that the bookmark points to.
        '';
      };

      description = mkOption {
        type = str;
        default = "";
        description = ''
          Description of the website that the bookmark points to.
        '';
      };
    };
  };

  # To support browser-specific lock flag,
  # expand the browser-specific enum, not this one.
  lockFlagEnum = [
    "allow-extension-installs"
    "allow-default-overrides"
    "allow-user-messaging-overrides"
    "allow-homepage-overrides"
  ];

  proxyConfig = {
    options = {
      locked = mkOption {
        type = bool;
        default = false;
        description = ''
          Whether the proxy options can be changed or not by the user.

          By default, it is always possible as an admin user may need
          to workaround a broken proxy configuration.

          Defense against proxy bypasses cannot rely on this option.

          This can be locked to avoid user errors, a firewall configuration
          needs to be enabled to ensure security.
        '';
      };

      noProxy = mkOption {
        type = listOf str;
        default = [ ];
        description = ''
          List of exempted URIs for the proxy.
        '';
      };

      autoConfigURL = mkOption {
        type = nullOr str;
        default = null;
        description = ''
          PAC URL to automatically configure the proxy.

          https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Proxy_servers_and_tunneling/Proxy_Auto-Configuration_PAC_file
        '';
      };

      httpProxy = mkOption {
        type = nullOr str;
        default = null;
        description = ''
          URL to the HTTP proxy.
          This proxy will be used for: SSL, FTP, SOCKS5 as well.

          SOCKS4 is not supported.
        '';
      };
    };
  };
}
