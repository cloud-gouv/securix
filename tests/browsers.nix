# SPDX-FileCopyrightText: 2026 risk-alt <aldu6974@gmail.com>
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }:
let
  terminal = libSecurix.mkTerminal {
    name = "browsers";
    userSpecificModule = { };
    vpnProfiles = { };
    modules = [
      {
        securix = {
          graphical-interface.variant = "sway";
          tools.enable = true;
          self = {
            mainDisk = "/dev/nvme0n1";
            machine = {
              hardwareSKU = "x280";
              serialNumber = "000000";
              inventoryId = 0;
            };
          };

          browser = {
            browsers = [
              "firefox"
              "chromium"
            ];

            bookmarks.Productivity.Github = {
              href = "https://github.com";
              icon = "si-github";
            };
          };
        };
      }
    ];
  };
in
pkgs.testers.nixosTest {
  name = "browsers";
  nodes = {
    securix-unbranded-0 = {
      imports = terminal.modules;
    };
  };
  testScript = ''
    import json

    securix = securix_unbranded_0
    securix.wait_for_unit("default.target")

    firefox = json.loads(securix.succeed("cat /etc/firefox/policies/policies.json"))["policies"]
    assert firefox["Homepage"]["URL"] == "http://127.0.0.1:8082", firefox["Homepage"]
    assert {
        "Title": "Github",
        "URL": "https://github.com",
        "Folder": "Productivity",
    } in firefox["Bookmarks"], firefox["Bookmarks"]
    assert firefox["ExtensionSettings"]["*"]["installation_mode"] == "blocked"

    chromium = json.loads(
        securix.succeed("cat /etc/chromium/policies/managed/extra.json")
    )
    assert chromium["SitePerProcess"] is True
    assert chromium["PasswordManagerEnabled"] is False
    assert chromium["ExtensionInstallBlocklist"] == ["*"]

    chromium_default = json.loads(
        securix.succeed("cat /etc/chromium/policies/managed/default.json")
    )
    assert chromium_default["HomepageLocation"] == "http://127.0.0.1:8082"

    securix.succeed("test -x /run/current-system/sw/bin/firefox")
    securix.succeed("test -x /run/current-system/sw/bin/chromium")

    securix.wait_for_unit("homepage-dashboard.service")
    securix.wait_for_open_port(8082)
  '';
}
