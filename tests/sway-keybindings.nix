# SPDX-FileCopyrightText: 2026 Quentin Cazier <cazierquentin@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# Regression test for https://github.com/cloud-gouv/securix/issues/84
#
# Boots the Securix sway configuration and drives it with key events sent
# by QEMU. The shortcuts must keep working on the same physical keys once
# the keyboard is switched from the default fr layout to a us layout.

{ pkgs, libSecurix }:

let
  lib = pkgs.lib;
in
pkgs.testers.nixosTest {
  name = "sway-keybindings";

  nodes.machine = {
    imports = [ ../modules/graphical-interface ];

    securix.graphical-interface = {
      enable = true;
      variant = "sway";
    };

    # Log in on tty1 directly instead of going through tuigreet.
    services.greetd.enable = lib.mkForce false;
    services.getty.autologinUser = "alice";

    users.users.alice = {
      isNormalUser = true;
      password = "test";
      uid = 1000;
    };

    environment.variables = {
      SWAYSOCK = "/tmp/sway-ipc.sock";
      WLR_RENDERER = "pixman";
    };

    programs.bash.loginShellInit = ''
      if [ "$(tty)" = "/dev/tty1" ]; then
        sway
      fi
    '';

    virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci" ];
  };

  testScript = ''
    import json
    import shlex

    def swaymsg(command, msg_type="command"):
        shell = "swaymsg -t " + shlex.quote(msg_type) + " -- " + shlex.quote(command)
        out = machine.succeed("su - alice -c " + shlex.quote(shell))
        return json.loads(out)

    def walk(node):
        yield node
        for group in ("nodes", "floating_nodes"):
            for child in node.get(group, []):
                yield from walk(child)

    def app_ids():
        return [node.get("app_id") for node in walk(swaymsg("", "get_tree"))]

    def focused_workspace():
        return [ws["num"] for ws in swaymsg("", "get_workspaces") if ws["focused"]][0]

    def keyboards():
        return [i for i in swaymsg("", "get_inputs") if i["type"] == "keyboard"]

    # QEMU names keys by their us position, so the fr "q" key is sent as "a".
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_file("/tmp/sway-ipc.sock")
    retry(lambda _: len(keyboards()) > 0, timeout_seconds=120)

    with subtest("fr layout: shortcuts work"):
        assert keyboards()[0]["xkb_active_layout_name"].startswith("French")
        machine.send_key("meta_l-ret")
        retry(lambda _: "foot" in app_ids(), timeout_seconds=120)
        machine.send_key("meta_l-shift-a")
        machine.wait_until_fails("pgrep foot")
        machine.send_key("meta_l-2")
        retry(lambda _: focused_workspace() == 2, timeout_seconds=120)

    with subtest("us layout: same physical keys"):
        swaymsg('input type:keyboard xkb_layout "fr,us"')
        swaymsg("input type:keyboard xkb_switch_layout 1")
        retry(lambda _: keyboards()[0]["xkb_active_layout_name"].startswith("English"), timeout_seconds=120)
        machine.send_key("meta_l-3")
        retry(lambda _: focused_workspace() == 3, timeout_seconds=120)
        machine.send_key("meta_l-ret")
        retry(lambda _: "foot" in app_ids(), timeout_seconds=120)
        machine.send_key("meta_l-shift-a")
        machine.wait_until_fails("pgrep foot")
  '';
}
