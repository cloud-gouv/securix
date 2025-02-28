# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ config, lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    mapAttrs
    filterAttrs
    listToAttrs
    concatStringsSep
    nameValuePair
    optionalString
    ;
  cfg = config.securix.bastions;
  entrypointOpts = _: {
    options = {
      name = mkOption {
        type = types.str;
        description = "Préfixe du FQDN pour ce bastion";
      };

      address = mkOption {
        type = types.str;
        description = "IPv4 ou IPv6 vers le Bastion";
      };

      publicSSHKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Clef SSH publique dudit bastion";
      };

      proxyJumps = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Liste (dans l'ordre) des jumps à appliquer pour atteindre la cible.";
      };
    };
  };

  entrypointsPerFQDN = listToAttrs (
    map (entry: nameValuePair "${entry.name}.${cfg.domainSuffix}" entry) cfg.entrypoints
  );
  mkKnownHostEntry = fqdn: value: {
    publicKey = value.publicSSHKey;
    extraHostNames = [ value.address ];
  };
  mkSshHostEntry =
    {
      name,
      proxyJumps,
      address,
      ...
    }:
    let
      translateEntry = e: builtins.replaceStrings [ "." ] [ "-" ] e;
      translatedProxyJumps = map translateEntry proxyJumps;
      fullName = translateEntry "${name}.${cfg.domainSuffix}";
      shortName = translateEntry name;
    in
    ''
      Host ${shortName} ${fullName}
        HostName ${address}
        IdentitiesOnly yes
        ${optionalString (proxyJumps != [ ]) "ProxyJump ${concatStringsSep ", " translatedProxyJumps}"}

      Match Host "${name}*,${shortName}*,${fullName}*,${address}*"
        IdentitiesOnly yes
        ${optionalString (proxyJumps != [ ]) "ProxyJump ${concatStringsSep ", " translatedProxyJumps}"}
    '';
in
{
  options.securix.bastions = {
    enable = mkEnableOption "génère les entrées statiques pour nos bastions";
    domainSuffix = mkOption {
      type = types.str;
      description = "Suffixe de domaine des bastions";
    };

    entrypoints = mkOption { type = types.listOf (types.submodule entrypointOpts); };
  };

  config = mkIf cfg.enable {
    # Register the known SSH key
    programs.ssh.knownHosts = mapAttrs mkKnownHostEntry (
      filterAttrs (n: v: v.publicSSHKey != null) entrypointsPerFQDN
    );
    # Register the /etc/hosts entry
    networking.extraHosts = ''
      ${concatStringsSep "\n" (
        map (entry: "${entry.address}\t${entry.name}.${cfg.domainSuffix}") cfg.entrypoints
      )}
    '';
    # Register the .ssh entry
    programs.ssh.extraConfig = ''
      ${concatStringsSep "\n" (map mkSshHostEntry cfg.entrypoints)}
    '';
    # TODO: register the Teleport entry?
  };
}
