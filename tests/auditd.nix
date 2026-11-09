# SPDX-FileCopyrightText: 2026 Alexander McHugh <alexanderedwardmchugh@gmail.com>
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }:
let
  mkAuditTerminal =
    inventoryId: lockRules:
    (libSecurix.mkTerminal {
      name = "auditd-${toString inventoryId}";
      userSpecificModule = { };
      vpnProfiles = { };
      modules = [
        {
          securix = {
            audit = {
              enable = true;
              adminEmail = "admin@example.com";
              inherit lockRules;
            };
            self = {
              mainDisk = "/dev/nvme0n1";
              machine = {
                hardwareSKU = "x280";
                inherit inventoryId;
              };
            };
          };
        }
      ];
    }).modules;

  # A 32-bit rm, to check that the compatibility syscall ABI is audited too.
  rm32 = "${pkgs.pkgsi686Linux.coreutils}/bin/rm";
in
pkgs.testers.nixosTest {
  name = "auditd";
  nodes = {
    # Node names must match the hostname Sécurix derives from the inventory id.
    securix-unbranded-0 = {
      imports = mkAuditTerminal 0 false;
      environment.systemPackages = [
        pkgs.python3
        pkgs.strace
      ];
    };
    securix-unbranded-1 = {
      imports = mkAuditTerminal 1 true;
    };
  };
  testScript = ''
    unlocked = securix_unbranded_0
    locked = securix_unbranded_1

    def audited(machine, key, needle):
        """Wait until an event with this key, matching needle, reaches the audit log."""
        try:
            machine.wait_until_succeeds(
                f"ausearch --input-logs -i -k {key} | grep -F -- '{needle}'", timeout=30
            )
        except Exception:
            _, out = machine.execute(
                f"ausearch --input-logs -i -k {key} | tail -n 20; "
                f"auditctl -l | grep -F 'key={key}'; auditctl -s; "
                "tail -n 5 /var/log/audit/audit.log; systemctl status auditd --no-pager | head"
            )
            print(f"=== audit diagnostics for key {key} ===\n{out}")
            raise

    start_all()

    with subtest("auditd runs with the Sécurix rule set loaded"):
        for m in (unlocked, locked):
            m.wait_for_unit("audit-rules-nixos.service")
            m.wait_for_unit("auditd.service")
            m.succeed("auditctl -l | grep -F 'key=kernel-modules'")

    with subtest("auditd.conf has no duplicate keys"):
        unlocked.succeed(
            "test -z \"$(grep -o '^[a-z_]*' /etc/audit/auditd.conf | sort | uniq -d)\""
        )
        unlocked.succeed("grep -x 'space_left = 10%' /etc/audit/auditd.conf")

    with subtest("every syscall rule exists for both ABIs"):
        b64 = int(unlocked.succeed("auditctl -l | grep -c 'arch=b64'"))
        b32 = int(unlocked.succeed("auditctl -l | grep -c 'arch=b32'"))
        assert b64 > 0 and b64 == b32, f"{b64} b64 rules, {b32} b32 rules"

    with subtest("kernel module loading and unloading"):
        unlocked.succeed("modprobe dummy && modprobe -r dummy")
        # NixOS modules are compressed, so modprobe decompresses them and
        # calls init_module rather than finit_module.
        audited(unlocked, "kernel-modules", "name=dummy")
        audited(unlocked, "kernel-modules", "syscall=delete_module")

    with subtest("kexec"):
        # kexec_file_load (320) with invalid file descriptors: the call
        # fails, but it is still audited.
        unlocked.succeed(
            "python3 -c 'import ctypes; ctypes.CDLL(None).syscall(320, -1, -1, 0, 0, 0)'"
        )
        audited(unlocked, "kexec", "kexec_file_load")

    with subtest("mount and unmount"):
        unlocked.succeed("mkdir -p /tmp/m && mount -t tmpfs none /tmp/m && umount /tmp/m")
        audited(unlocked, "mount", "syscall=mount")
        audited(unlocked, "mount", "syscall=umount2")

    with subtest("hostname change"):
        unlocked.succeed("hostname audit-test")
        audited(unlocked, "hostname", "sethostname")

    with subtest("ptrace"):
        unlocked.succeed("strace -o /dev/null true")
        audited(unlocked, "ptrace", "syscall=ptrace")

    with subtest("program execution"):
        unlocked.succeed("printf '#!/bin/sh\\n' > /tmp/marker-script && chmod +x /tmp/marker-script && /tmp/marker-script")
        audited(unlocked, "exec", "/tmp/marker-script")

    with subtest("file deletion, through both ABIs"):
        unlocked.succeed("touch /tmp/del64 && rm /tmp/del64")
        audited(unlocked, "file-deletion", "/tmp/del64")
        unlocked.succeed("touch /tmp/del32 && ${rm32} /tmp/del32")
        audited(unlocked, "file-deletion", "/tmp/del32")
        unlocked.succeed(
            "ausearch --input-logs -i -k file-deletion -f /tmp/del32 | grep 'arch=i386'"
        )

    with subtest("denied file access"):
        unlocked.succeed("useradd -m mallory")
        unlocked.fail("su mallory -c 'cat /etc/shadow'")
        audited(unlocked, "access-denied", "/etc/shadow")

    with subtest("configuration changes under /etc"):
        unlocked.succeed("echo x > /etc/audit-marker")
        audited(unlocked, "etc", "/etc/audit-marker")

    with subtest("tampering with the audit trail and tools"):
        unlocked.succeed("cat /var/log/audit/audit.log > /dev/null")
        audited(unlocked, "audit-log", "/var/log/audit/audit.log")
        unlocked.succeed("auditctl -s")
        audited(unlocked, "audit-tools", "auditctl")

    with subtest("no audit events were lost, from boot onwards"):
        for m in (unlocked, locked):
            lost = int(m.succeed("auditctl -s | awk '$1 == \"lost\" { print $2 }'"))
            assert lost == 0, f"{m.name}: {lost} audit events lost"

    with subtest("unlocked rules can be changed at runtime"):
        unlocked.succeed("auditctl -s | grep -x 'enabled 1'")

    with subtest("locked rules cannot be removed, even by root"):
        locked.succeed("auditctl -s | grep -x 'enabled 2'")
        locked.fail("auditctl -D")
        locked.fail("auditctl -e 0")
        locked.fail("auditctl -w /tmp -p wa")
        locked.succeed("auditctl -l | grep -F 'key=kernel-modules'")
  '';
}
