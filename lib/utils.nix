# SPDX-FileCopyrightText: 2025 Elias Coppens <elias.coppens@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT
{ lib, ... }:
{
  address =
    let
      ipv4-regex = "((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)";
      ipv6-regex = "(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))";
    in
    rec {
      isIPv4WithoutSubnet = address: (lib.match "^${ipv4-regex}$" address) != null;

      isIPv4WithSubnet = address: (lib.match "^${ipv4-regex}[/](3[0-2]|[1-2]?[0-9])$" address) != null;

      isIPv4 = address: (isIPv4WithoutSubnet address) || (isIPv4WithSubnet address);

      isIPv6WithoutSubnet =
        address: (lib.match "^(${ipv6-regex})|([[]${ipv6-regex}[]])$" address) != null;

      isIPv6WithSubnet =
        address: (lib.match "^${ipv6-regex}[/](12[0-8]|1[0-1][1-9]|[0-9]?[0-9])$" address) != null;

      isIPv6 = address: (isIPv6WithoutSubnet address) || (isIPv6WithSubnet address);
    };
}
