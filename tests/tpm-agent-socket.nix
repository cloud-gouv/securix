# SPDX-FileCopyrightText: 2026 Sébastien Celles <s.celles@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# Regression test for https://github.com/cloud-gouv/securix/issues/296:
# with TPM-sealed host keys, the system ssh-tpm-agent socket lives in /run
# (root only, cleared at boot), not in world-writable /var/tmp, and sshd
# and the agent work through it.

{ pkgs, libSecurix }:
let
  terminal = libSecurix.mkTerminal {
    name = "tpm-agent-socket";
    userSpecificModule = { };
    vpnProfiles = { };
    modules = [
      {
        securix = {
          ssh.tpm-agent.hostKeys = true;
          graphical-interface.variant = "sway";
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
  name = "tpm-agent-socket";
  nodes.securix-unbranded-0 = {
    imports = terminal.modules;
    virtualisation.tpm.enable = true;
  };
  testScript = ''
    machine = securix_unbranded_0
    machine.wait_for_unit("ssh-tpm-agent.socket")
    machine.succeed("test \"$(stat -c '%U %a' /run/ssh-tpm-agent.sock)\" = 'root 600'")
    machine.fail("test -e /var/tmp/ssh-tpm-agent.sock")
    machine.succeed("grep -x 'HostKeyAgent /run/ssh-tpm-agent.sock' /etc/ssh/sshd_config")
    # The agent answers on the socket with the TPM-sealed host key.
    machine.wait_until_succeeds("SSH_AUTH_SOCK=/run/ssh-tpm-agent.sock ssh-add -L | grep -q ecdsa", timeout=120)
  '';
}
