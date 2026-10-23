# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ pkgs, lib, ... }: {
  boot.initrd.systemd.enable = lib.mkDefault true;

  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/etc/secureboot";
    # Keep a bounded number of signed, bootable generations (rollback stays
    # possible) instead of every past one.
    configurationLimit = lib.mkDefault 10;
  };

  environment.systemPackages = [ pkgs.sbctl ];
}
