# SPDX-FileCopyrightText: 2025 Elias Coppens <elias.coppens@numerique.gouv.fr>
# SPDX-FileContributor: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
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
    head
    listToAttrs
    map
    mkIf
    mkEnableOption
    mkOption
    types
    nameValuePair
    unique
    mapAttrs
    splitString
    optional
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
      getIpFromEndpoint = endpoint: head (splitString ":" endpoint);

      private-key = "${ykman} piv objects export ${wgPiv} - | ${age} -d -i <(${age-yubikey} -i --slot ${agePiv}) -";

      default-gw = "$(${ip} route show default | grep -v ${itf} | awk '{print $3}')";

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
        ${concatStringsSep "\n" (
          concatMap (
            peer:
            [ "${ip} route add ${getIpFromEndpoint peer.endpoint} via ${default-gw}" ]
            ++ map (allowedCidr: "${ip} route add ${allowedCidr} dev ${itf}") peer.ips
          ) peers
        )}
      '';

      downScript = pkgs.writeShellScript "wireguard-${wireguardName}-down" ''
        ${ip} link del dev "${itf}"
        ${concatStringsSep "\n" (
          map (peer: "${ip} route delete ${getIpFromEndpoint peer.endpoint} via ${default-gw}") peers
        )}
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

    rosenpass = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        defaultText = lib.literalExpression "config.securix.vpn.wireguard.enable";
        description = ''
          Livre l'outillage d'échange de clés post-quantique `rosenpass`
          dans le PATH système. Rosenpass superpose un KEM post-quantique
          standardisé NIST au-dessus du handshake Noise de WireGuard,
          neutralisant le risque « harvest now, decrypt later » contre
          le handshake Curve25519 de WG.

          Cette option n'installe que les binaires ; l'activation par
          profil est opt-in (voir `docs/rosenpass.md` ou le README
          WireGuard Sécurix). Désactiver cette option masque simplement
          les binaires — cela ne casse pas les connexions WG existantes.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.wireguard-tools
      pkgs.age
      pkgs.age-plugin-yubikey
    ]
    ++ optional cfg.rosenpass.enable pkgs.rosenpass;

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
      ) (builtins.attrNames operators);
    };
  };
}
