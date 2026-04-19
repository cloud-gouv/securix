# SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
#
# SPDX-License-Identifier: MIT

# Post-quantum hybrid key exchange for IPsec / IKEv2 (RFC 9370).
#
# strongSwan 6.x ships with native ML-KEM support via the openssl
# plugin when built against OpenSSL 3.5+ — which is already the case
# on nixpkgs 25.11 (OpenSSL 3.6). Enabling PQ IKE is therefore not
# about adding a plugin or a crypto overlay (AWS-LC, botan3) but about
# *appending an additional KE round* to the existing IKE proposal
# strings configured per-VPN in the inventory.
#
# RFC 9370 defines additional KE rounds chained with the primary
# Diffie-Hellman (classical) group. The resulting session key is
# derived from BOTH — so the session remains secure as long as *one*
# of the two components resists an adversary. With classical X25519
# paired with ML-KEM-768, a `harvest-now-decrypt-later` attacker
# needs to break *both* to recover past traffic.
#
# When this module's `enable = true`, every IKE proposal generated
# for a NetworkManager strongSwan connection gets `-ke1_mlkem768`
# appended (or the operator-chosen `additionalKe`). strongSwan and
# NetworkManager handle fallback automatically: if the peer does not
# support RFC 9370, the additional-KE round is simply skipped and a
# classical-only session is established.
#
# Zero-disruption rollout: legacy peers still work, modern peers get
# PQ. No rebuild, no overlay, just a string suffix.
{ config, lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.securix.vpn.ipsec.postQuantum = {
    enable = mkEnableOption ''
      hybrid post-quantum key exchange for IPsec IKEv2 proposals.
      Appends an additional KE round (default ML-KEM-768) to every
      per-VPN IKE proposal. Requires strongSwan 6.x (already shipped
      in nixpkgs 25.11) on both sides. Peers without RFC 9370 support
      fall back to classical negotiation transparently.
    '';

    additionalKe = mkOption {
      type = types.str;
      default = "ke1_mlkem768";
      description = ''
        Additional KE suffix appended to the IKE proposal.
        Must match the strongSwan proposal syntax for RFC 9370:

          ke1_mlkem512    — ML-KEM-512   (NIST PQ security level 1)
          ke1_mlkem768    — ML-KEM-768   (NIST PQ level 3, recommended)
          ke1_mlkem1024   — ML-KEM-1024  (NIST PQ level 5)

        `ke2_*`, `ke3_*` etc. chain additional rounds; generally not
        useful unless you're experimenting with crypto diversification.
      '';
      example = "ke1_mlkem1024";
    };
  };
}
