# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ lib, config, ... }: 
let
  inherit (lib) mkEnableOption mkOption types mkIf genAttrs;
  cfg = config.securix.anssi;
in
{
  options.securix.anssi = {
    enable = mkEnableOption "ANSSI compliance";

    rules = mkOption {
      type = types.listOf (types.enum [
        "r1"
        "r2"
        "r3"
        "r4"
        "r5"
        "r6"
        "r7"
        # TODO: R8
        # TODO: R9
        # TODO: R10
        # TODO: R10 requires kernel module disablement, that's not realistic for our usecases.
        # TODO: R11
        # TODO: R12
        # R13 means disabling IPv6 and we do not agree with this rule.
        # TODO: R14.
        # Kernel hardening
        # TODO: R15
        # TODO: R16
        # TODO: R17
        # TODO: R18
        # TODO: R19
        # TODO: R20
        # TODO: R21
        # TODO: R22
        # TODO: R23
        # TODO: R24 (32 bits systems).
        # TODO: R25
        # TODO: R26 (ARM systems).
        # TODO: R27 (ARM64 systems).
        # End of kernel hardening
        # TODO: R28.
        # TODO: R29 auto-mount units for /boot.
        # TODO: R30 already performed. 
        # TODO: R31 enable some blanket password policy.
        # TODO: R32 — use sneslock.
        # TODO: R33 enable auditd.
        # TODO: R34 assert that nobody is not used in any systemd service.
        # TODO: R35 kinda done.
        # TODO: R36
        # TODO: R37 - AppArmor.
        # TODO: R38 — `operator` group.
        # TODO: R39.
        # TODO: R40. 
        # TODO: R41 — produce a clear list of EXEC directives for review.
        # TODO: R42 — assert that negations are not present. 
        # TODO: R43 — warn about wildcards. 
        # TODO: R44.
        # TODO: R45 — same as R37. 
        # TODO: R46/R47/R48/R49: not applicable. 
        # TODO: R50 — assert. 
        # TODO: R51 — done by default. 
        # TODO: R52 — done by default. 
        # TODO: R53 — done by default. 
        # TODO: R54 — assert.
        # TODO: R55 — pam_mktemp.
        # TODO: R56 — list all SUID binaries. 
        # TODO: R57 — same as above. 
        # TODO: R58 — list all packages and offers profiles (ops, etc.). 
        # TODO: R59 — done by NixOS. 
        # TODO: R60 — done by NixOS. 
        # TODO: R61 — update system.
        # TODO: R62 — review enabled services. 
        # TODO: R63 — review enabled services. 
        # TODO: R64 — systemd-analyze security output. 
        # TODO: R65 — systemd hardening. 
        # TODO: R66 — same as above. 
        # TODO: R67 — offer PAM hardening options. 
        # TODO: R68 — yescrypt mandated. 
        # TODO: R69 — we don't use NSS. 
        # TODO: R70 — not applicable. 
        # TODO: R71 — journald. 
        # TODO: R72 — journald + auditd. 
        # TODO: R73 — auditd. 
        # TODO: R74 — no mailing system.
        # TODO: R75 — same as above. 
        # TODO: R76 — dm-verity (absolute immutability) + fs-verity (in certain scenarios).
        # TODO: R77 — dm-verity + root access. 
        # TODO: R78 — systemd hardening + network namespaces. 
        # TODO: R79 — SSH for remote administration. 
        # TODO: R80 — same as above ^.
      ]);

      default = [
        "r1"
        "r2"
        "r3"
        "r4"
        "r5"
        "r6"
        "r7"
      ];
    };
  };

  imports = 
  # Auto-load any file in ./rules.
  let
    rule-modules = builtins.readDir ./rules;
  in
  map (path: ./${path}) (builtins.attrNames rule-modules);

  config = mkIf cfg.enable {
    securix.anssi-rules = genAttrs cfg.rules (n: { enable = true; });
  };
}
