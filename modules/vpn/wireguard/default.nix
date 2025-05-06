# SPDX-FileCopyrightText: 2025 Elias Coppens <elias.coppens@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  vpnProfiles,
  operators,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.securix.vpn.wireguard;

  inherit (lib)
    attrValues
    concatMap
    concatMapStringsSep
    concatStringsSep
    elem
    filter
    hasAttr
    listToAttrs
    map
    mkIf
    mkEnableOption
    nameValuePair
    unique
    mapAttrs
    ;

  selectWireguardVpns =
    list:
    filter (vpnName: hasAttr vpnName vpnProfiles && vpnProfiles.${vpnName}.type == "wireguard") list;

  # Utilities commands
  wg = "${pkgs.wireguard-tools}/bin/wg";
  ip = "${pkgs.iproute2}/bin/ip";
  ykman = "${pkgs.yubikey-manager}/bin/ykman";
  age = "${pkgs.age}/bin/age";
  age-yubikey = "${pkgs.age-plugin-yubikey}/bin/age-plugin-yubikey";

  # Create users scripts to run
  mkWireGuardScripts =
    {
      wireguardName,
      username,
      bit,
    }:
    let
      wireguard = vpnProfiles.${wireguardName};
      itf = wireguard.interface;
      address = wireguard.mkAddress bit;
      wgPiv = wireguard.wireguardPivSlot;
      agePiv = toString wireguard.agePivSlot;
      port = toString wireguard.listenPort;
      peers = wireguard.peers;

      private-key = "${ykman} piv objects export ${wgPiv} - | ${age} -d -i <(${age-yubikey} -i --slot ${agePiv}) -";

      mkPeerString =
        peer:
        ''peer "${peer.publicKey}" endpoint "${peer.endpoint}" allowed-ips "${concatStringsSep "," peer.ips}"'';

      # TODO: maybe use Network namespace ?
      upScript = pkgs.writeShellScript "wireguard-${wireguardName}-up" ''
        ${ip} link add dev "${itf}" type wireguard
        ${ip} address add ${address} dev ${itf}

        ${wg} set "${itf}" listen-port ${port} \
          private-key <(${private-key}) \
          ${concatMapStringsSep " " mkPeerString peers}

        ${ip} link set up dev "${itf}"
      '';

      downScript = pkgs.writeShellScript "wireguard-${wireguardName}-down" ''
        ${ip} link del dev "${itf}"
      '';
    in
    rec {
      management = pkgs.writeShellScriptBin "wireguard-${wireguardName}" ''
        # ${username}
        verb=$1

        if [[ "$verb" = "up" ]]; then
          ${upScript}
        elif [[ "$verb" = "down" ]]; then
          ${downScript}
        else
          echo "Unrecognized option $verb: please choose between up or down"
        fi
      '';

      genkey = pkgs.writeShellScriptBin "wireguard-${wireguardName}-genkey" ''
        ${importkey}/bin/wireguard-${wireguardName}-importkey <(${wg} genkey)
      '';

      pubkey = pkgs.writeShellScriptBin "wireguard-${wireguardName}-pubkey" ''
        echo "The wireguard public key is: $(${private-key} | ${wg} pubkey)"
      '';

      importkey = pkgs.writeShellScriptBin "wireguard-${wireguardName}-importkey" ''
        ${age-yubikey} --list --slot ${agePiv} > /dev/null

        if [[ $? -ne 0 ]]; then
          echo "Age certificate is not created, will create it:"

          ${age-yubikey} --generate \
            --slot ${agePiv} --pin-policy once --touch-policy always
        fi

        ${ykman} piv objects import ${wgPiv} \
          <(cat $1 | ${age} -e -r $(${age-yubikey} --list --slot ${agePiv} | tail -n 1) -a -)

          ${pubkey}/bin/wireguard-${wireguardName}-pubkey

      '';
    };
in
{
  options.securix.vpn.wireguard = {
    enable = mkEnableOption "the Wireguard VPN subsystem";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.wireguard-tools
      pkgs.age
      pkgs.age-plugin-yubikey
    ];

    users.users = mapAttrs (username: config: {
      packages = concatMap (
        wireguardName:
        attrValues (mkWireGuardScripts {
          inherit wireguardName username;
          inherit (config) bit;
        })
      ) (selectWireguardVpns config.allowedVPNs);
    }) operators;

    security.sudo = {
      enable = true;
      extraRules = concatMap (
        username:
        map (wg: {
          users = [ username ];
          commands = [
            {
              # User-specific binaries.
              command = "/etc/profiles/per-user/${username}/bin/wireguard-${wg}";
              options = [ "NOPASSWD" ];
            }
          ];
        }) (selectWireguardVpns operators.${username}.allowedVPNs)
      ) operators;
    };
  };
}
