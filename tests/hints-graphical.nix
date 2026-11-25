# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }:
let
  terminal = libSecurix.mkTerminal {
    name = "hints-graphical";
    userSpecificModule = { };
    vpnProfiles = { };
    extraOperators = {
      alice = {
        securix.self.username = "alice";
        securix.self.fullName = "Alice";
        securix.self.isAdmin = true;
        securix.self.yubikey = { };
      };
    };
    modules = [
      {
        securix = {
          graphical-interface = {
            enable = true;
            variant = "kde";
          };
          self = {
            mainDisk = "/dev/nvme0n1";
            machine = {
              hardwareSKU = "x280";
              inventoryId = 0;
            };
          };
          hints.enable = true;
        };

        virtualisation = {
          memorySize = 4096;
          cores = 2;
          graphics = true;
          diskSize = 8192;
        };

        services.xserver.enable = true;
        services.displayManager.autoLogin.enable = true;
        services.displayManager.autoLogin.user = "alice";

        users.users.alice.isNormalUser = true;
        users.users.alice.password = "";
        users.users.alice.initialPassword = "";
        users.groups.hints = { };
        users.users.alice.group = "hints";

        boot.loader.systemd-boot.enable = true;
      }
    ];
  };
in
pkgs.testers.nixosTest {
  name = "hints-graphical";
  skipLint = true;
  nodes = {
    securix-unbranded-0 = {
      imports = terminal.modules;
    };
  };
  testScript = ''
    start_all()
    securix_unbranded_0.wait_for_unit("default.target")
    securix_unbranded_0.wait_for_unit("securix-hintd.service")

    listing = securix_unbranded_0.succeed("ls -ln /run/securix-hints/ 2>&1")
    assert "consumer.sock" in listing, listing

    securix_unbranded_0.wait_until_succeeds("pgrep -u alice plasmashell", timeout=180)

    securix_unbranded_0.succeed(
        "securix-hintctl set --source demo --key reboot --kind reboot "
        "--severity 2 --title 'Redémarrage requis' "
        "--body 'Une mise à jour attend. Redémarrez pour l activer.' "
        "--action 'snooze:Plus tard'"
    )

    securix_unbranded_0.wait_until_succeeds(
        "runuser -u alice -- /run/current-system/sw/bin/securix-hintctl list | grep -q demo",
        timeout=120,
    )

    securix_unbranded_0.sleep(86400)
  '';
}
