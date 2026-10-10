# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ pkgs, lib, ... }: {
  boot.initrd.systemd.enable = lib.mkDefault true;

  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/etc/secureboot";
    # Boot entries cannot be edited from the boot menu: Lanzaboote's stub
    # only ignores an edited command line while Secure Boot is enforced.
    settings.editor = lib.mkDefault false;
    # Keep a bounded number of signed, bootable generations (rollback stays
    # possible) instead of every past one.
    configurationLimit = lib.mkDefault 10;
  };

  environment.systemPackages = [ pkgs.sbctl ];
}
