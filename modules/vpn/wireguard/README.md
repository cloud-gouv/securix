<!--
SPDX-FileCopyrightText: 2025 Elias Coppens <elias.coppens@numerique.gouv.fr>
SPDX-FileContributor: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
SPDX-FileContributor: 2026 Aurélien Ambert <aurelien.ambert@proton.me>

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

## Échange de clés post-quantique (Rosenpass)

Le handshake natif de WireGuard utilise **Curve25519** (ECDH
classique). Un attaquant capable d'enregistrer le handshake aujourd'hui
pourrait, une fois les
[CRQC](https://en.wikipedia.org/wiki/Cryptographically_relevant_quantum_computer)
disponibles, dériver les clés de session rétroactivement et déchiffrer
tout le trafic capturé — le classique risque *harvest-now-decrypt-later*.

[Rosenpass](https://rosenpass.eu) superpose un KEM post-quantique
standardisé NIST (hybride Classic McEliece + CRYSTALS-Kyber)
**par-dessus** le handshake WireGuard et injecte un PSK rafraîchi dans
chaque peer au moment de l'accord de clé. WireGuard intègre ensuite ce
PSK dans son état Noise, de sorte que même une connaissance complète
du handshake Curve25519 ne permet pas le déchiffrement.

### Pré-requis

`securix.vpn.wireguard.rosenpass.enable = true;` (défaut quand
`wireguard.enable = true`) garantit que le binaire `rosenpass` est
dans le PATH système.

### Mise en place unique par profil

1. **Générer une paire de clés Rosenpass sur chaque peer** (les deux côtés, une seule fois) :

   ```bash
   sudo rosenpass gen-keys --secret-key /etc/rosenpass/<profile>.sk \
                            --public-key /etc/rosenpass/<profile>.pk
   ```

2. **Échanger les clés publiques** avec l'admin du peer via un canal
   authentifié (email+GPG, Signal, en présentiel). Copier la `.pk` du
   peer dans `/etc/rosenpass/<profile>.peer.pk`.

3. **Activer le service rosenpass système** (module NixOS upstream)
   avec la configuration de votre profil :

   ```nix
   services.rosenpass = {
     enable = true;
     defaultDevice = "wg0";  # doit matcher votre interface WG
     settings = {
       public_key = "/etc/rosenpass/<profile>.pk";
       secret_key = "/etc/rosenpass/<profile>.sk";
       listen = [ "0.0.0.0:9999" ];  # UDP, port distinct de WG
       peers = [
         {
           public_key = "/etc/rosenpass/<profile>.peer.pk";
           endpoint = "<peer-ip>:9999";
           # Le PSK que Rosenpass injecte via `wg set peer <wg-pubkey> preshared-key -`
         }
       ];
     };
   };
   ```

4. **Monter WG comme d'habitude** — `wireguard-<profile> up`. L'unité
   systemd `rosenpass.service` démarre à côté, négocie un PSK PQ avec
   le peer, et fait tourner en continu le PSK qu'elle injecte dans
   l'interface WG.

### Caveats

- Rosenpass utilise un **port UDP séparé** de WireGuard (typiquement
  9999). Veiller à ce que votre firewall l'autorise entre les peers.
- Rosenpass n'authentifie pas le peer par lui-même — il s'appuie sur
  le handshake à clé publique de l'étape 2. Perdre le contrôle de la
  `.pk` d'un peer casse la couche PQ (le WG classique continue de
  fournir l'authentification via la clé publique Curve25519).
- Rosenpass ajoute ~50 ms à chaque fenêtre de re-key (par défaut
  toutes les ~2 minutes). Négligeable pour des sessions admin.
- Non testé avec des clés Rosenpass portées par YubiKey — le démon
  lit la `.sk` sur disque. Pour un keypair PQ matériel, suivre les
  issues Rosenpass upstream.

### Modèle de menace après Rosenpass

| Contre | WG seul | WG + Rosenpass |
|---|---|---|
| Aujourd'hui : extraction de clé depuis handshake capturé | ✓ protégé (Curve25519 solide) | ✓ |
| Aujourd'hui : MITM actif avec privkey peer WG volée | ✗ tunnel détourné | ✗ toujours détournable (Rosenpass s'appuie sur l'auth WG) |
| **2035+ : déchiffrement du trafic capturé aujourd'hui via CRQC** | ✗ **vulnérable** | ✓ **protégé (McEliece + Kyber)** |
