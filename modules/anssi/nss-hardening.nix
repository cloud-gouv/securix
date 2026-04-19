# SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
#
# SPDX-License-Identifier: MIT

# ANSSI R66 — Restreindre les mécanismes de résolution de noms.
#
# NSS (Name Service Switch) dispatches all lookups for hosts, users,
# groups, services, etc. through a list of pluggable backends. Every
# backend in `/etc/nsswitch.conf` is a potential attack surface:
#
#   * `mdns4_minimal` / `mdns6_minimal` (Avahi) — passive mDNS queries
#     leak local interests on the LAN and open DNS-spoofing paths via
#     link-local resolution.
#   * `nis`, `nisplus`, `wins`, `winbind` — legacy auth/name protocols
#     with known weaknesses; none should appear on a modern Sécurix
#     workstation.
#   * `mymachines` (systemd-machined) — container name resolution, not
#     needed on an end-user workstation.
#   * `myhostname` (nss-myhostname) — translates the local hostname
#     to an IP. Useful inside Docker, dead-weight on a workstation
#     where `/etc/hosts` already maps the hostname.
#
# After this rule, `/etc/nsswitch.conf` contains only `files + dns`
# on the `hosts:` line (plus `files [success=merge] systemd` on
# passwd/group which stay for systemd-sysusers integration).
{
  R66 = {
    name = "R66_NSSHardening";
    anssiRef = "R66 – Restreindre les mécanismes de résolution de noms";
    description = ''
      Disable non-essential NSS backends (mDNS, NIS, WINS, mymachines,
      myhostname) so that name resolution only traverses the explicitly
      trusted paths: /etc/hosts (files) and DNS.
    '';
    severity = "intermediary";
    category = "base";
    tags = [ "nss-hardening" ];

    config =
      { lib, ... }:
      {
        # Prevent Avahi from injecting mDNS backends into nsswitch even
        # if services.avahi.enable becomes true later (defensive).
        services.avahi.nssmdns4 = lib.mkForce false;
        services.avahi.nssmdns6 = lib.mkForce false;

        # Strictly limit the `hosts:` lookup chain. Sites that need
        # systemd-resolved (DNSSEC) can add `"resolve"` via a lower-
        # priority override (mkOverride 90) or disable this rule.
        system.nssDatabases.hosts = lib.mkForce [
          "files"
          "dns"
        ];
      };

    checkScript =
      pkgs:
      pkgs.writeShellScript "check-R66" ''
        # Fail if any forbidden NSS backend appears anywhere in
        # /etc/nsswitch.conf. Uses -w for word-boundary so "mdns"
        # catches "mdns4_minimal" / "mdns6_minimal" / "mdns" equally.
        status=0
        for bad in mdns mdns4 mdns4_minimal mdns6 mdns6_minimal nis nisplus wins winbind mymachines myhostname; do
          if ${pkgs.gnugrep}/bin/grep -qwE "$bad" /etc/nsswitch.conf; then
            echo "FAIL: /etc/nsswitch.conf contains forbidden backend '$bad'"
            status=1
          fi
        done
        if [ $status -eq 0 ]; then
          echo "PASS: nsswitch.conf is restricted to files+dns+systemd"
        fi
        exit $status
      '';
  };
}
