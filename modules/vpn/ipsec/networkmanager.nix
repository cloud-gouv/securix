# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  pkgs,
  vpnProfiles,
  operators,
  config,
  lib,
  ...
}:
let
  cfg = config.securix.vpn.ipsec;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    nameValuePair
    concatMapAttrs
    concatStringsSep
    listToAttrs
    mapAttrs
    mapAttrs'
    mapAttrsToList
    filter
    hasAttr
    filterAttrs
    mergeAttrsList
    mkDefault
    ;
  isValidIpsecProfile =
    profileName: hasAttr profileName vpnProfiles && vpnProfiles.${profileName}.type == "ipsec";
  mapValidIpsecProfiles =
    f: profiles:
    map (profileName: f profileName vpnProfiles.${profileName}) (filter isValidIpsecProfile profiles);
  ipsecProxies = concatMapAttrs (
    op: opCfg:
    # We merge all the available HTTP proxies together.
    mergeAttrsList (
      mapValidIpsecProfiles
        (
          profileName: profile:
          # We keep a back pointer to which VPN this proxy is attached to.
          # NOTE(Ryan): this means that multiple VPNs which refers to the same proxy as default.
          (mapAttrs (_: proxy: proxy // { vpn = profileName; }) profile.availableHttpProxies)
        )
        # We ignore every VPNs that has NO proxies.
        (
          filter (
            profileName:
            hasAttr profileName vpnProfiles && (vpnProfiles.${profileName}.availableHttpProxies or { }) != { }
          ) opCfg.allowedVPNs
        )
    )
  ) operators;
  mkIPsecConnectionProfile =
    operatorName:
    {
      username,
      email,
      bit,
      ...
    }:
    profileName:
    {
      endpoint,
      remote-identity,
      method,
      ike,
      esp,
      remoteSubnets,
      localSubnet,
      gateway ? null,
      mkPasswordVariable ? null,
      mkAddress ? null,
      ...
    }:
    assert lib.assertMsg (bit != null)
      "Il n'est pas possible de générer un profil IPsec si le paramètre `bit` n'est pas rempli pour l'administrateur ${operatorName}";
    assert lib.assertMsg (mkPasswordVariable == null -> method != "psk")
      "Si la méthode PSK est spécifié pour le tunnel `${profileName}`, une façon de récupérer le mot de passe via une variable d'environnement doit etre spécifié.";
    assert lib.assertMsg (mkAddress == null -> localSubnet == "%any")
      "Si aucune méthode de construction d'adresse IP dans le tunnel `${profileName}` n'est spécifié, alors le mode config d'IPsec doit etre configuré pour la configuration IP automatique.";
    assert lib.assertMsg (gateway == null -> localSubnet == "%any")
      "Si aucune gateway dans le tunnel `${profileName}` n'est spécifié, alors le mode config d'IPsec doit etre configuré pour la configuration IP automatique.";
    {
      connection = {
        id = "VPN ${profileName} for ${operatorName}";
        autoconnect = true;
        # This locks down this VPN entry only for that user.
        permissions = "user:${username};";
        type = "vpn";
      };

      vpn =
        {
          address = endpoint;
          remote-identity = mkIf (remote-identity != null) remote-identity;
          encap = "yes";
          ipcomp = "no";
          # It's automatically derived when the cert is on the smartcard.
          local-identity = mkIf (method != "cert-on-security-token") email;
          proposal = "yes";
          inherit ike esp;
          remote-ts = concatStringsSep ";" remoteSubnets;
          local-ts = mkIf (mkAddress != null) (mkAddress bit);
          virtual = if (localSubnet == "%any") then "yes" else "no";
          service-type = "org.freedesktop.NetworkManager.strongswan";
        }
        // (
          if method == "cert-on-security-token" then
            {
              method = "smartcard";
              cert-source = "smartcard";
              password-flags = 1; # Ask the agent for the PIN.
            }
          else
            {
              method = "psk";
              password-flags = 0;
            }
        );

      vpn-secrets = mkIf (method == "psk") { password = mkPasswordVariable operatorName; };

      ipv4 = {
        method = if localSubnet == "%any" then "disabled" else "auto";
        address1 = mkIf (localSubnet != "%any") "${mkAddress bit},${gateway}";
        ignore-auto-dns = true;
      };

      ipv6 = {
        method = "disabled";
      };
    };

  mkCertificateAuthorityFile = certName: path: {
    name = "${certName}.crt";
    value.file = path;
  };
in
{
  options.securix.vpn.ipsec = {
    enable = mkEnableOption "the IPsec connection";

    certificateAuthorityFiles = mkOption {
      type = types.attrsOf types.path;
      default = { };
      description = ''
        When IPsec is used with a security key, a mutual authentication is performed between the client and the server.
        StrongSwan do NOT use the system-wide trust store to assess server identity.

        It makes use of a custom path that needs to collect every certificate as a flat file.

        To make this simple on operators, you can pass an attribute set of certificate files in this list and those will be
        added to the IPsec trust store under the name they are passed.
      '';
    };

    pskSecretsPaths = mkOption {
      type = types.attrsOf types.path;
      default = { };
      description = "Chemin vers toutes les PSKs, non nécessaire en mode certificats.";
    };
  };

  config = mkIf cfg.enable {
    age.secrets = mapAttrs (_: path: { file = path; }) cfg.pskSecretsPaths;

    # This is an extra rule to allow any user to do `sudo pkill charon-nm` to reset the VPN state.
    # Sometimes, when you suspend your system while having the VPN enabled and you get out of suspend state.
    # The `charon-nm` process which stands for Charon NetworkManager is still running even though your VPN is down due to getting out of suspend and having lost Internet.
    # When you try to bring up the VPN again, your VPN will not come up because `charon-nm` blocks the spawn of a new `charon-nm` process, displaying a weird
    # "Cannot activate VPN due to missing secrets" error message.
    # This is clearly a Strongswan bug but we do not have the resources and time to perform root cause analysis on this bug and submit a patch or bug report to Strongswan.
    # FIXME: Find the time to do it.
    security.sudo.extraRules = [
      {
        groups = [ "operator" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/pkill charon-nm";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    environment.etc = {
      "strongswan.conf".text = ''
        charon-nm {
          ca_dir = /etc/ipsec.d/certs
          plugins {
            pkcs11 {
              modules {
                opensc {
                  path = ${pkgs.opensc}/lib/opensc-pkcs11.so
                }
              }
            }
          }
        }
      '';
    } // mapAttrs' mkCertificateAuthorityFile cfg.certificateAuthorityFiles;

    systemd.services.NetworkManager.serviceConfig.Environment = [
      "STRONGSWAN_CONF=/etc/strongswan.conf"
    ];

    # Add all available proxies and default proxies for
    # IPsec VPN profiles.
    securix.automatic-http-proxy = {
      enable = mkDefault true;
      proxies = ipsecProxies;
    };
    # Automatically switch to the default proxy of the
    # enabled VPN.
    networking.networkmanager.dispatcherScripts =
      let
        defaultProxiesPerVPN = filterAttrs (n: arg: arg.default or false) ipsecProxies;
        mkSwitchFor =
          proxyName:
          { vpn, ... }:
          ''
            # Hook for ${vpn}
            # Default proxy: ${proxyName}
            if [[ "$CONNECTION_ID" == "VPN ${vpn} for $user" ]]; then
              logger "[IPsec proxy hook] Automatically switching to proxy ${proxyName}"
              ${pkgs.proxy-switcher}/bin/proxy-switcher ${proxyName} --cli
              # FIXME(Ryan): this hardcodes the SSH forward method for this proxy.
              # We should check if that's needed and perhaps encode `bringupLogic` as a property of the proxy.
              systemctl --user -M "$user"@ stop "ssh-tunnel-to-*" --all
              systemctl --user -M "$user"@ start ssh-tunnel-to-${proxyName}.service
            else
              logger "[IPsec proxy hook] Skipping ${proxyName} for $CONNECTION_ID as it doesn't match $user-${vpn}.nmconnection"
            fi
          '';
      in
      [
        {
          type = "basic";
          source = pkgs.writeText "10-automatic-proxy-switch-up-hook" ''
            if [ "$2" != "vpn-up" ]; then
              logger "exit: event $2, waiting for a vpn-up event"
              exit
            fi

            # This retrieves the caller user of the dispatcher.
            # NOTE(Ryan): this logic is brittle. on a multi-seat system,
            # there's multiple results.
            # NetworkManager should pass who sent the D-Bus message as an environment variable.
            user=$(loginctl list-sessions --no-legend | ${pkgs.gawk}/bin/awk '{print $3}' | sort -u | grep -vE '^(root|gdm)$')
            ${concatStringsSep "\n" (mapAttrsToList mkSwitchFor defaultProxiesPerVPN)}
          '';
        }
        {
          type = "basic";
          source = pkgs.writeText "20-automatic-proxy-switch-down-hook" ''
            if [ "$2" != "vpn-down" ]; then
              logger "exit: event $2, waiting for a vpn-down event"
              exit
            fi
            # This retrieves the caller user of the dispatcher.
            # NOTE(Ryan): this logic is brittle. on a multi-seat system,
            # there's multiple results.
            # NetworkManager should pass who sent the D-Bus message as an environment variable.
            user=$(loginctl list-sessions --no-legend | ${pkgs.gawk}/bin/awk '{print $3}' | sort -u | grep -vE '^(root|gdm)$')
            systemctl --user -M "$user"@ stop "ssh-tunnel-to-*" --all
            ${pkgs.proxy-switcher}/bin/proxy-switcher np
          '';
        }
      ];

    networking.networkmanager.plugins = [ pkgs.networkmanager_strongswan ];
    networking.networkmanager.ensureProfiles.environmentFiles = mapAttrsToList (
      name: _: config.age.secrets.${name}.path
    ) cfg.pskSecretsPaths;
    networking.networkmanager.ensureProfiles.profiles = concatMapAttrs (
      op: opCfg:
      listToAttrs (
        mapValidIpsecProfiles (
          profileName: profile:
          nameValuePair "${op}-${profileName}" (mkIPsecConnectionProfile op opCfg profileName profile)
        ) opCfg.allowedVPNs
      )
    ) operators;
  };
}
