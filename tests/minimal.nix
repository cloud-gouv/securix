# SPDX-FileCopyrightText: 2025 Antoine Eiche <aei.ext@hackcyom.com>
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }:
let
  terminal = libSecurix.mkTerminal {
    name = "minimal";
    userSpecificModule = {
      securix.self = {
        allowedVPNs = [ "ipsec-test" ];
      };
    };
    vpnProfiles = {
      ipsec-test = {
        type = "ipsec";
        endpoint = "192.168.1.100";
        remote-identity = null;
        method = "psk";
        ike = "aes256-sha256-modp2048";
        esp = "aes256-sha256-modp2048";
        mkAddress = bit: "10.0.0.1/32";
        localSubnet = "10.0.0.1/24";
        gateway = "10.0.1.253";
        remoteSubnets = [ "100.64.0.0/20" ];
        mkPasswordVariable = _: "$PSK_FOR_VPN";
      };
    };
    extraOperators = {
      "test" = {
        securix.self = {
          username = "test";
          email = "test@test.com";
          allowedVPNs = [ "ipsec-test" ];
        };
      };
    };
    modules = [
      {
        securix = {
          graphical-interface.variant = "sway";
          vpn.ipsec = {
            enable = true;
            proxies.map.ipsec-test = "local_securix";
          };
          automatic-http-proxy = {
            implementation = "portail";
            proxies = {
              local_securix = {
                vpn = "ipsec-test";
                default = true;
                remote = {
                  address = "10.1.1.1";
                  port = 8081;
                };
                auth.sshForward = {
                  enable = false;
                };
              };
            };
          };
          self = {
            mainDisk = "/dev/nvme0n1";
            machine = {
              hardwareSKU = "x280";
              serialNumber = "000000";
            };
          };
        };
      }
    ];
  };
in
pkgs.testers.nixosTest {
  name = "minimal";
  nodes = {
    securix-unbranded-000000 = {
      imports = terminal.modules;
    };
  };
  testScript = ''
    securix_unbranded_000000.wait_for_unit("default.target")
    securix_unbranded_000000.succeed("cat /etc/os-release | grep securix")
  '';
}
