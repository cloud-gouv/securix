<!--
SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# SSH post-quantum posture on Sécurix

State of the art as of early 2026. This page covers which parts
of the SSH protocol used on Sécurix workstations are already
post-quantum safe, which parts are **not yet** and why, and what
Sécurix offers today to narrow the gap.

---

## TL;DR

| Layer | PQ today | Gap / mitigation |
|---|---|---|
| Session keys (KEX) | 🟢 Hybrid ML-KEM-768 + X25519 by default | Opt-in strict mode removes the classical fallback (`securix.ssh.pqc.enforceKex = true`). |
| Host key signatures | 🔴 Ed25519 / ECDSA / RSA only | No upstream PQ signature in OpenSSH yet. Mitigation: short host-key lifetime, frequent rotation. |
| User key signatures | 🔴 Same as host keys | Same mitigation. |
| Cipher / MAC | 🟢 AES-256-GCM / ChaCha20-Poly1305 | Symmetric — only a quadratic (Grover) speedup; 128-bit security floor remains. |

---

## Session keys — KEX

OpenSSH 9.9+ (shipped in nixpkgs 25.11) supports two
standards-track post-quantum hybrid key-exchange algorithms:

- `mlkem768x25519-sha256` — NIST [FIPS 203](https://csrc.nist.gov/pubs/fips/203/final)
  (ML-KEM-768) combined with classical X25519. The pair's shared
  secret is PQ-safe if **either** component resists the adversary.
- `sntrup761x25519-sha512` — CRYSTALS predecessor paired with
  X25519, battle-tested since OpenSSH 9.0.

The nixpkgs default `KexAlgorithms` places these **first** in the
ClientHello, so any modern-to-modern SSH handshake on Sécurix is
PQ hybrid. However the default **also** keeps classical
curve25519 and DH group-exchange as a fallback for legacy peers —
a network attacker who can drop or rewrite the PQ offer can
silently force a downgrade to classical (MITM-style), yielding a
handshake whose session keys are only classical-strong.

### Strict mode

When the Sécurix fleet is PQ-capable end-to-end, enable strict
mode:

```nix
securix.ssh.pqc.enforceKex = true;
```

This narrows `KexAlgorithms` to the three PQ hybrids only. Any
peer without PQ support is rejected at the handshake (`no matching
key exchange method found`), removing the downgrade vector.

### Compatibility matrix

| Peer runtime | Default (fallback OK) | `enforceKex = true` |
|---|---|---|
| OpenSSH 9.9+ (Ubuntu 24.04, Debian 13, RHEL 9.5+, NixOS 24.05+) | 🟢 PQ | 🟢 PQ |
| OpenSSH 9.0 – 9.8 | 🟡 PQ via sntrup761 | 🟢 PQ via sntrup761 |
| OpenSSH 8.x (Debian 11, RHEL 8, Ubuntu 20.04) | 🟢 classical | 🔴 rejected |
| PuTTY ≥ 0.81 | 🟢 PQ | 🟢 PQ |
| PuTTY < 0.81 | 🟢 classical | 🔴 rejected |
| Termux (recent) | 🟢 PQ | 🟢 PQ |

---

## Host & user key signatures

This is where SSH is **not** post-quantum safe today. Every host
key and every user key on a Sécurix workstation is Ed25519 or
ECDSA (via `ssh-tpm-agent` for TPM-sealed keys). Both are broken
by Shor's algorithm: a cryptographically relevant quantum
computer recovers the private key from a handful of captured
signatures.

### Why no fix?

OpenSSH upstream has not merged support for PQ signature schemes
as of the 10.x series (February 2026). The candidate algorithms
are:

- **ML-DSA** (NIST FIPS 204, "CRYSTALS-Dilithium") — signatures
  ~2–3 KB
- **SLH-DSA** (NIST FIPS 205, "SPHINCS+") — signatures ~8–17 KB

Both are many times larger than Ed25519 (64 B) and require
changes to the SSH wire format. [Patches from Open Quantum Safe][oqs]
exist but are explicitly research-grade and lag upstream.

[oqs]: https://github.com/open-quantum-safe/openssh

### Threat model

- **Today's signatures are exposed** to anyone who can observe an
  SSH handshake (ISP, corporate tap, public Wi-Fi, captured server
  firewall logs).
- **A future CRQC is needed to break them** — NIST / NSA IAD /
  ANSSI consensus estimates a 10–15 year horizon (2035–2040) for a
  cryptographically relevant quantum computer, but this is deeply
  uncertain.
- **Key extraction ⇒ forgery ⇒ authentication bypass.** An
  attacker who recovers a Sécurix host key via a future CRQC can
  impersonate the host on any new connection. User-key recovery
  enables impersonation of the operator.

### Mitigations available today

1. **Frequent rotation.** If a host key lives only 30 days, a CRQC
   breakthrough in year *N* cannot be used against signatures from
   year *N-1*: the old key is already retired and no system trusts
   it. Rotating TPM-sealed host keys requires re-enrolling the
   fingerprint at every client's `known_hosts` — not free.
2. **TPM sealing.** Does **not** save the classical signature from
   being forgeable, but prevents *offline* key extraction: an
   attacker who steals the disk cannot pull the private key.
3. **SSH certificates with short TTL.** Replace per-host trust
   with a CA-signed certificate whose `valid after` window is
   hours, not years. The CA key is still classical, but the
   attack surface per key is tiny.
4. **Layer a PQ transport under SSH.** A PQ VPN (IPsec with
   ML-KEM, WireGuard + Rosenpass) carrying SSH gives the session
   keys two PQ layers. Signatures inside SSH remain classical, but
   an attacker must break both the VPN KEX and the SSH KEX to
   reach the signature layer.

Sécurix ships options for 1, 2, and 4 today
(`securix.ssh.tpm-agent.*`, `securix.vpn.ipsec.*`,
`securix.vpn.wireguard.*`). Option 3 (short-TTL CA) is on the
roadmap but not yet implemented.

---

## What to watch upstream

- [OpenSSH release notes](https://www.openssh.com/releasenotes.html)
  for PQ signature support.
- [OQS-OpenSSH](https://github.com/open-quantum-safe/openssh) for
  experimental PQ signature previews (not production-ready).
- [IETF draft-ietf-tls-hybrid-design](https://datatracker.ietf.org/doc/draft-ietf-tls-hybrid-design/)
  — the broader hybrid-PQ framework; SSH work usually follows TLS.

When OpenSSH ships ML-DSA, Sécurix will add it to
`HostKeyAlgorithms` and recommend a migration path in a follow-up
to this document.
