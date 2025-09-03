# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  imports = [
    ./journal.nix
    ./console.nix
    ./distribution.nix
    ./bootloader.nix
    ./filesystems.nix
    ./networking.nix
    ./power-saving.nix
    ./authorized-users.nix
    ./package-manager.nix
    # Automatic setup of SSH tunnels
    ./ssh-forward.nix
    # Autoconfiguration of OpenStack
    ./openstack-client.nix
    # The management of our entrypoints for our static bastions.
    ./bastion
    # Known hosts for our clouds.
    ./known-hosts.nix
    # SOCKS5 proxy for API and documentation access
    ./g3proxy
    ./http-proxy
    # Our Root CAs
    ./pki.nix
    ./shells.nix
    # Allow SSH keys from the TPM to be exposed through the agent
    ./ssh-tpm-agent.nix
    # Audit logs
    ./auditd.nix
    # Data-only pertaining to the system
    ./self.nix
    # All the VPN code
    ./vpn
    # Superadmins options
    ./superadmins
    # All the administration tools
    ./tools
    # Graphical interfaces
    ./graphical-interface
    # Security keys configuration.
    ./security-keys.nix
    # Automatic update system
    ./updates
    # For observability of Securix
    ./o11y
  ];
}
