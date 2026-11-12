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
          hints.enable = true;
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

    # The daemon runs without privilege, in its own runtime directory.
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
    state = securix_unbranded_0.succeed(
        "systemctl show securix-hintd.service -p RuntimeDirectory --value"
    )
    assert state.strip() == "securix-hints", state

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

    # A restart keeps the hints. The store is on disk.
    securix_unbranded_0.succeed("test -f /run/securix-hints/hints.json")
    securix_unbranded_0.succeed("securix-hintctl set --source persist --key k --title Kept")
    securix_unbranded_0.succeed("systemctl restart securix-hintd.service")
    securix_unbranded_0.succeed("securix-hintctl get persist k | grep -q Kept")

    # A producer removes its hints.
    securix_unbranded_0.succeed("securix-hintctl clear-source test")
    securix_unbranded_0.succeed("securix-hintctl clear-source persist")
    securix_unbranded_0.succeed("securix-hintctl list | grep -q '\"hints\": \\[\\]'")
  '';
}
