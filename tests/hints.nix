# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }:
let
  terminal = libSecurix.mkTerminal {
    name = "hints";
    userSpecificModule = { };
    vpnProfiles = { };
    modules = [
      {
        securix = {
          self = {
            mainDisk = "/dev/nvme0n1";
            machine = {
              hardwareSKU = "x280";
              inventoryId = 0;
            };
          };
          hints = {
            enable = true;
            autoRebootAfterSeconds = 28800;
            # Use another name, to prove the option reaches the producer.
            criticalSource = "test-kernel";
          };
        };

        # Make the removal of expired hints fast.
        systemd.services.securix-hintd.environment.SECURIX_HINTS_SWEEP_INTERVAL_SECONDS = "2";
      }
    ];
  };
in
pkgs.testers.nixosTest {
  name = "hints";
  nodes = {
    securix-unbranded-0 = {
      imports = terminal.modules;
    };
  };
  testScript = ''
    securix_unbranded_0.wait_for_unit("default.target")
    securix_unbranded_0.wait_for_unit("securix-hintd.service")

    # The daemon uses the sockets from systemd. The permissions are correct.
    securix_unbranded_0.succeed("test -S /run/securix-hints/control.sock")
    securix_unbranded_0.succeed("test -S /run/securix-hints/consumer.sock")
    securix_unbranded_0.succeed("test \"$(stat -c '%a' /run/securix-hints/control.sock)\" = 600")
    securix_unbranded_0.succeed("test \"$(stat -c '%a' /run/securix-hints/consumer.sock)\" = 666")

    # The daemon runs without privilege, and root owns the sockets.
    securix_unbranded_0.succeed(
        "systemctl show securix-hintd.service -p DynamicUser --value | grep -qx yes"
    )
    securix_unbranded_0.succeed(
        "systemctl show securix-hintd.service -p NoNewPrivileges --value | grep -qx yes"
    )
    securix_unbranded_0.succeed(
        "systemctl show securix-hintd.service -p PrivateTmp --value | grep -qx yes"
    )
    securix_unbranded_0.succeed(
        "systemctl show securix-hintd.service -p UID --value | grep -qxv 0"
    )
    securix_unbranded_0.succeed(
        "test \"$(stat -c '%U:%G' /run/securix-hints/control.sock)\" = root:securix-hints-control"
    )

    # A producer writes a hint. A reader reads it.
    securix_unbranded_0.succeed(
        "securix-hintctl set --source test --key reboot --title 'Reboot required' --severity 2"
    )
    securix_unbranded_0.succeed("securix-hintctl list | grep -q 'Reboot required'")
    securix_unbranded_0.succeed("securix-hintctl get test reboot | grep -q 'Reboot required'")
    securix_unbranded_0.succeed("securix-hintctl status | grep -q '\"hint_count\": 1'")

    # A hint expires. The daemon removes it.
    securix_unbranded_0.succeed(
        "securix-hintctl set --source test --key expired --title 'Expired hint' --severity 1 --expires-at 1"
    )
    securix_unbranded_0.wait_until_succeeds(
        "! securix-hintctl list | grep -q 'Expired hint'"
    )

    # The option reaches the producer: the timer writes under the new name.
    securix_unbranded_0.succeed(
        "grep -q 'source=test-kernel' $(command -v securix-hints-kernel-reboot)"
    )

    # The kernel timer proposes a reboot only if a new kernel waits. The uptime
    # sets the severity.
    kernel = "/nix/store/00000000000000000000000000000000-linux-6.13.0/bzImage"

    def run_timer(running, uptime):
        securix_unbranded_0.succeed(
            f"SECURIX_HINTS_TARGET_KERNEL={kernel} "
            f"SECURIX_HINTS_RUNNING_KERNEL={running} "
            f"SECURIX_HINTS_UPTIME_SECONDS={uptime} "
            "securix-hints-kernel-reboot"
        )

    # One day on an old kernel. The hint is advisory.
    run_timer("6.12.34", 86400)
    securix_unbranded_0.succeed("securix-hintctl get test-kernel reboot | grep -q '\"severity\": 1'")
    securix_unbranded_0.succeed("securix-hintctl get test-kernel reboot | grep -q 'Redémarrer maintenant'")
    securix_unbranded_0.succeed("securix-hintctl get test-kernel reboot | grep -q 'Plus tard'")

    # Four days. The hint is important.
    run_timer("6.12.34", 345600)
    securix_unbranded_0.succeed("securix-hintctl get test-kernel reboot | grep -q '\"severity\": 2'")

    # Six days. The machine reboots itself. The hint is critical.
    run_timer("6.12.34", 518400)
    securix_unbranded_0.succeed("securix-hintctl get test-kernel reboot | grep -q '\"severity\": 3'")
    securix_unbranded_0.fail("securix-hintctl get test-kernel reboot | grep -q 'Plus tard'")

    # The kernel is the same. There is no hint.
    run_timer("6.13.0", 345600)
    securix_unbranded_0.fail("securix-hintctl get test-kernel reboot")

    # A fresh update. There is no hint.
    run_timer("6.12.34", 3600)
    securix_unbranded_0.fail("securix-hintctl get test-kernel reboot")

    # The module passes the configuration to the agent unit.
    unit = securix_unbranded_0.succeed("cat /etc/systemd/user/securix-hint-agent.service")
    assert "SECURIX_HINTS_AUTO_REBOOT_AFTER_SECONDS=28800" in unit, unit
    assert "SECURIX_HINTS_CRITICAL_SOURCE=test-kernel" in unit, unit

    # A restart keeps the hints. The store is on disk.
    environ = securix_unbranded_0.succeed(
        r"tr '\0' '\n' < /proc/$(pidof securix-hintd)/environ"
    )
    runtime = next(
        line.split("=", 1)[1]
        for line in environ.splitlines()
        if line.startswith("RUNTIME_DIRECTORY=")
    )
    securix_unbranded_0.succeed(f"test -f {runtime}/hints.json")
    securix_unbranded_0.succeed("securix-hintctl set --source persist --key k --title Kept")
    securix_unbranded_0.succeed("systemctl restart securix-hintd.service")
    securix_unbranded_0.succeed("securix-hintctl get persist k | grep -q Kept")

    # A producer removes its hints.
    securix_unbranded_0.succeed("securix-hintctl clear-source test")
    securix_unbranded_0.succeed("securix-hintctl clear-source persist")
    securix_unbranded_0.succeed("securix-hintctl list | grep -q '\"hints\": \\[\\]'")
  '';
}
