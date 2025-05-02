<!--
SPDX-FileCopyrightText: 2025 Elias Coppens <elias.coppens@numerique.gouv.fr>
SPDX-FileContributor: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>

SPDX-License-Identifier: MIT
-->

# WireGuard(R) VPN module for Sécurix

## How it works

The WireGuard VPN module supports the YubiKey Series 5 (other security keys have not yet been tested).

It securely stores the WireGuard private key using the following approach:

- An **age key pair** is generated and stored on a PIV certificate slot of the YubiKey. The **private key never leaves the YubiKey**: data is encrypted using the public key and decrypted directly on the device.
- A **WireGuard private key** is generated, **encrypted with the YubiKey’s age public key**, and stored in a PIV object slot on the YubiKey.

When the VPN is enabled, the encrypted WireGuard private key is read from the YubiKey, **decrypted on the device**, and passed to the WireGuard process.

Since the decrypted WireGuard key must be available in memory for WireGuard to function, **regular key rotation is recommended** for enhanced security.

Here's a reworked, clearer version of your documentation:

## Using WireGuard VPN Profiles

Sécurix provides a system for managing VPN profiles. To configure a WireGuard VPN, add a profile like this:

```nix
{
  <vpn-name> = {
    type = "wireguard";
    interface = "wg0";

    # List of internal VPN addresses used by the Sécurix client
    addresses = [
      <IP addresses>
    ];

    # WARNING: This will erase any existing data in the selected object PIV slot
    wireguardPivSlot = "5f0000"; # Choose any PIV object slot (hex string)

    # WARNING: This will erase any existing data in the selected certificate PIV slot
    agePivSlot = 14; # Must be an integer between 1 and 20

    listenPort = 58120;

    peers = [
      {
        publicKey = "<peer's WireGuard public key>";
        endpoint = "<peer IP>:<peer port>";
        ips = [
          <IP addresses the peer is allowed to use>
        ];
      }
    ];
  };
}
```

## Managing the WireGuard VPN

Once your VPN profile is installed, use the following commands to manage it:

- `wireguard-<vpn-name>-genkey`  
  Generates and encrypts the WireGuard private key using your YubiKey.  
  This must be done once to set up the profile.

- `wireguard-<vpn-name>-pubkey`  
  Computes the corresponding public key from the generated private key.  
  Useful for sharing with VPN peers.

- `wireguard-<vpn-name> up`  
  Activates the VPN using the private key decrypted by the YubiKey.

- `wireguard-<vpn-name> down`  
  Deactivates the VPN.
