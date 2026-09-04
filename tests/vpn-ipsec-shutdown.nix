# SPDX-FileCopyrightText: 2025 Antoine Eiche <aei.ext@hackcyom.com>
# SPDX-FileContributor: 2026 Sofiane Beloucif <beloucif.sofiane16@gmail.com>
#
# SPDX-License-Identifier: MIT

# Regression test for https://github.com/cloud-gouv/securix/issues/205:
# a hung `charon-nm` process (strongSwan's NetworkManager IPsec plugin) must
# not block `NetworkManager.service` from stopping for more than a bounded
# amount of time.
{ pkgs, libSecurix }:
let
  terminal = libSecurix.mkTerminal {
    name = "vpn-ipsec-shutdown";
    userSpecificModule = { };
    vpnProfiles = { };
    modules = [
      {
        securix = {
          # graphical-interface.variant is read unconditionally by some
          # sub-modules (e.g. cinnamon.nix) regardless of `enable`, so a
          # value must be provided even though we don't need a graphical
          # session for this test.
          graphical-interface.variant = "sway";
          self = {
            mainDisk = "/dev/nvme0n1";
            machine = {
              hardwareSKU = "x280";
              inventoryId = 0;
            };
          };
          vpn.ipsec.enable = true;
        };
      }
    ];
  };
in
pkgs.testers.nixosTest {
  name = "vpn-ipsec-shutdown";
  nodes = {
    securix-unbranded-0 = {
      imports = terminal.modules;
      # The default test VM (1 vCPU / 1024 MiB) is too tight for Sécurix's
      # full module closure (in particular the sizeable package set pulled
      # in unconditionally by modules/tools) under nested virtualisation,
      # where udev/systemd device processing can fall far enough behind to
      # blow past the default device-unit timeouts. Give the VM more room.
      virtualisation.memorySize = 4096;
      virtualisation.cores = 4;
    };
  };
  testScript = ''
    import time

    securix_unbranded_0.wait_for_unit("NetworkManager.service")

    # Our mitigation must bound how long systemd waits for
    # NetworkManager.service to stop...
    securix_unbranded_0.succeed(
        "systemctl show NetworkManager.service -p TimeoutStopUSec | grep -q '=10s'"
    )
    # ...but what actually bounds shutdown/reboot itself is the system-wide
    # default, since systemd-shutdown's final kill sweep isn't governed by
    # any per-unit TimeoutStopSec. See the comment in
    # modules/vpn/ipsec/networkmanager.nix for why.
    securix_unbranded_0.succeed(
        "systemctl show -p DefaultTimeoutStopUSec | grep -q '=10s'"
    )

    # Simulate a `charon-nm` process still alive in NetworkManager's cgroup
    # and ignoring SIGTERM, like the real strongSwan bug this mitigates.
    # Use a real file named `charon-nm` (rather than `exec -a` to rename
    # argv[0]) so its `comm` is "charon-nm" regardless of the shell used to
    # launch it.
    #
    # It must never fork a child to sleep/wait: a forked child is placed in
    # whatever cgroup its parent is in *at fork time*. Since we move this
    # process into NetworkManager's cgroup only *after* spawning it (see
    # below), a child forked beforehand would stay in its original cgroup
    # and never receive the SIGTERM systemd broadcasts to NetworkManager's
    # cgroup -- only the process directly moved there does. A signal-trapping
    # busy loop avoids forking altogether, so it (and only it) reliably
    # keeps ignoring SIGTERM once moved.
    #
    # NOTE: the write/chmod and the backgrounded spawn are deliberately two
    # separate machine.succeed() calls. The test driver's execute() pipes the
    # command's stdout through `base64 -w0; echo` and waits for that pipe to
    # close. Backgrounding a whole `a && b && c &` chain in a single call
    # backgrounds the *entire* and-or list as one job; only the final command
    # (setsid ...) has its own local `>/dev/null` redirection, so the pipe
    # ends up not fully closing and execute() hangs forever. Backgrounding
    # only the already fully-redirected `setsid ...` command by itself, as
    # its own call, avoids that.
    securix_unbranded_0.succeed(
        "printf '#!/bin/sh\\ntrap : TERM\\nwhile :; do :; done\\n' > /root/charon-nm && "
        "chmod +x /root/charon-nm"
    )
    securix_unbranded_0.succeed("setsid /root/charon-nm </dev/null >/dev/null 2>&1 &")
    securix_unbranded_0.wait_until_succeeds("pgrep -x charon-nm")
    securix_unbranded_0.succeed(
        "pid=$(pgrep -x charon-nm); "
        "echo $pid > /sys/fs/cgroup/system.slice/NetworkManager.service/cgroup.procs"
    )

    # Actually shut the machine down, rather than just `systemctl stop`ping
    # NetworkManager.service in isolation: the real bug manifests during the
    # system-wide shutdown sequence, where systemd waits for every unit's
    # cgroup to empty before it can proceed. A standalone `systemctl stop`
    # can return as soon as the unit's main process exits, without actually
    # waiting on stray processes like our simulated charon-nm, so it would
    # not reliably exercise (or catch a regression in) TimeoutStopSec here.
    start = time.monotonic()
    securix_unbranded_0.shutdown()
    elapsed = time.monotonic() - start

    assert elapsed < 60, (
        f"shutting down took {elapsed:.1f}s, expected it to be bounded by "
        "TimeoutStopSec (10s) rather than the default 90s"
    )
  '';
}
