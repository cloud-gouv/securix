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
  cfg = config.securix.vpn;
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
    mapAttrsToList
    optionalAttrs
    ;
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
      defaultProxy ? null,
      availableHttpProxies ? { },
      ...
    }:
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

      user =
        {
          "securix.username" = username;
        }
        // optionalAttrs (defaultProxy != null) {
          "securix.default_http_proxy_ip" = "${availableHttpProxies.${defaultProxy}}";
          "securix.default_http_proxy_name" = defaultProxy;
        };
    };
in
{
  options.securix.vpn = {
    enable = mkEnableOption "the IPsec connection";

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

    environment.etc."strongswan.conf".text = ''
      charon-nm {
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

    nixpkgs.overlays = [
      (self: super: {
        strongswan = super.strongswan.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ ./support-local-ts.patch ];
        });
      })
    ];

    systemd.services.NetworkManager.serviceConfig.Environment = [
      "STRONGSWAN_CONF=/etc/strongswan.conf"
    ];

    networking.networkmanager.enableStrongSwan = true;
    networking.networkmanager.ensureProfiles.environmentFiles = mapAttrsToList (
      name: _: config.age.secrets.${name}.path
    ) cfg.pskSecretsPaths;

    networking.networkmanager.dispatcherScripts = [
      {
        type = "basic";
        source = pkgs.writeText "securix-vpn-hooks" ''
          iface=$1
          action=$2
          user=$CONNECTION_USER_SECURIX__USERNAME
          default_http_proxy_ip=$CONNECTION_USER_SECURIX__DEFAULT_HTTP_PROXY_IP
          default_http_proxy_name=$CONNECTION_USER_SECURIX__DEFAULT_HTTP_PROXY_NAME
          if [ "$action" == "vpn-up" ]; then
            logger "[securix-vpn-hooks] stopping local HTTP proxy to let remote VPN HTTP proxy take over..."
            systemctl stop http-proxy.service && logger "[securix-vpn-hooks] local HTTP proxy stopped successfully" || logger "[securix-vpn-hooks] local HTTP proxy failed to stop"
            systemctl start --user "$user" "vpn-http-proxy-tunnel@$default_http_proxy_ip.service" && logger "[securix-vpn-hooks] authenticated to the VPN HTTP proxy '$default_http_proxy_name' successfully" || logger "[securix-vpn-hooks] failed to authenticate to the VPN HTTP proxy"
          fi
          if [ "$action" == "vpn-down" ]; then
            logger "[securix-vpn-hooks] stopping remote VPN HTTP proxy to let local HTTP proxy take over..."
            systemctl stop --user "$user" vpn-http-proxy-tunnel.target && logger "[securix-vpn-hooks] failed to stop the remote VPN HTTP proxy" || logger "[securix-vpn-hooks] remote VPN HTTP proxy stopped successfully"
            systemctl start http-proxy.service && logger "[securix-vpn-hooks] local HTTP proxy started successfully" || logger "[securix-vpn-hooks] local HTTP proxy failed to start"
            # Ensure that any charon-nm process has been killed to avoid the classical error "no vpn secrets" available.
            ${pkgs.procps}/bin/pkill charon-nm && logger "[securix-vpn-hooks] terminated `charon-nm` ipsec process" || logger "[securix-vpn-hooks] `charon-nm` already exited, no need for killing it."
          fi
        '';
      }
    ];

    networking.networkmanager.ensureProfiles.profiles = concatMapAttrs (
      op: opCfg:
      listToAttrs (
        map (
          profileName:
          nameValuePair "${op}-${profileName}" (
            mkIPsecConnectionProfile op opCfg profileName vpnProfiles.${profileName}
          )
        ) opCfg.allowedVPNs
      )
    ) operators;
  };
}
