# SPDX-FileCopyrightText: 2025 Antoine Eiche <aei.ext@hackcyom.com>
# SPDX-FileContributor: 2026 Sébastien Celles <s.celles@gmail.com>
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }:
let
  terminal = libSecurix.mkTerminal {
    name = "minimal";
    userSpecificModule = { };
    vpnProfiles = { };
    modules = [
      {
        securix = {
          graphical-interface.variant = "kde";
          ssh.tpm-agent.hostKeys = true;
          self = {
            mainDisk = "/dev/nvme0n1";
            machine = {
              hardwareSKU = "x280";
              inventoryId = 0;
            };
          };
        };
        services.openssh.enable = true;
      }
    ];
  };
in
pkgs.testers.nixosTest {
  name = "minimal";
  nodes = {
    securix-unbranded-0 = {
      imports = terminal.modules;
      virtualisation.tpm.enable = true;
    };
  };
  testScript = ''
    securix_unbranded_0.wait_for_unit("default.target")
    securix_unbranded_0.succeed("cat /etc/os-release | grep securix")

    # Regression test for https://github.com/cloud-gouv/securix/issues/296:
    # with TPM-sealed host keys the system ssh-tpm-agent socket lives in /run
    # (root only, cleared at boot), not in world-writable /var/tmp, and sshd
    # and the agent work through it.
    securix_unbranded_0.wait_for_unit("ssh-tpm-agent.socket")
    securix_unbranded_0.succeed("test \"$(stat -c '%U %a' /run/ssh-tpm-agent.sock)\" = 'root 600'")
    securix_unbranded_0.succeed("grep -x 'HostKeyAgent /run/ssh-tpm-agent.sock' /etc/ssh/sshd_config")
    # The agent answers on the socket with the TPM-sealed host key.
    securix_unbranded_0.wait_until_succeeds("SSH_AUTH_SOCK=/run/ssh-tpm-agent.sock ssh-add -L | grep -q ecdsa", timeout=120)
  '';
}
